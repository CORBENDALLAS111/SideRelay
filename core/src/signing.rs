use crate::{Config, Session, failure::Failure};
use isideload::{
    anisette::{AnisetteProvider, remote_v3::RemoteV3AnisetteProvider},
    auth::apple_account::{AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse},
    dev::{developer_session::DeveloperSession, devices::DevicesApi, teams::TeamsApi},
    sideload::{
        SideloaderBuilder,
        builder::{ExtensionsBehavior, ExtensionsBehaviorSelection, MaxCertsBehavior},
    },
    util::{
        callbacks::{ExtensionsBehaviorCallbackBox, MaxCertsCallbackBox},
        storage::InMemoryStorage,
    },
};
use serde_json::json;
use std::{path::PathBuf, sync::Arc};
use zeroize::Zeroize;

pub async fn sign(
    config: &mut Config,
    udid: &str,
    session: Arc<Session>,
) -> Result<PathBuf, String> {
    session.progress(
        "auth",
        0.15,
        "Входим в Apple Account. Пароль не сохраняется…",
    );
    let two_factor = session.clone();
    let callback = move |params: TwoFactorCallbackParams| {
        let s = two_factor.clone();
        async move {
            s.diagnostic("AUTH_2FA_REQUESTED");
            // Never put upstream last_error strings in the UI/event queue.
            let hint = if params.last_error.is_some() {
                "Apple не принял предыдущее подтверждение. Запроси свежий код или выбери другой способ."
            } else if params.unknown {
                "Выбери, куда отправить код: на доверенные устройства или по SMS."
            } else {
                "Введи свежий код с доверенного устройства или из SMS."
            };
            let answer = s
                .answer(
                    "two_factor",
                    json!({"numbers":params.numbers,"sms":params.sms,"hint":hint,"unknown":params.unknown}),
                )
                .await
                .map_err(|_| rootcause::report!("2FA cancelled"))?;
            Ok(match answer["action"].as_str().unwrap_or("") {
                "code" => TwoFactorCallbackResponse::SubmitCode(
                    answer["value"].as_str().unwrap_or("").to_string(),
                ),
                "sms" => {
                    TwoFactorCallbackResponse::SendSms(answer["value"].as_u64().unwrap_or(0) as u32)
                }
                "devices" => TwoFactorCallbackResponse::SendToDevices,
                "resend" => TwoFactorCallbackResponse::ResendCode,
                _ => TwoFactorCallbackResponse::Abort,
            })
        }
    };
    let anisette = RemoteV3AnisetteProvider::new(
        config.anisette.trim_end_matches('/'),
        Box::new(InMemoryStorage::new()),
        "0".into(),
    )
    .map_err(|_| "Не удалось настроить anisette")?;
    session.diagnostic("AUTH_ANISETTE_INFO");
    let info = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        anisette.get_client_info(),
    )
    .await
    .map_err(|_| fail(&session, "Anisette не ответил", Failure::Timeout))?
    .map_err(|e| {
        fail(
            &session,
            "Не удалось проверить anisette",
            Failure::from_report(&e),
        )
    })?;
    // Use the server's own client description throughout provisioning and login.
    // Report only the platform, never the server payload or identity.
    session.diagnostic(if info.client_info.contains("Windows") {
        "AUTH_ADI_WINDOWS"
    } else if info.client_info.contains("Android") {
        "AUTH_ADI_ANDROID"
    } else {
        "AUTH_ADI_OTHER"
    });
    session.diagnostic("AUTH_APPLE_LOOKUP");
    let mut account = tokio::time::timeout(
        std::time::Duration::from_secs(45),
        AppleAccount::builder(config.email.trim())
            .anisette_provider(anisette)
            .err_429_retries(Some(0))
            .build(),
    )
    .await
    .map_err(|_| {
        fail(
            &session,
            "Apple не ответил при подготовке входа",
            Failure::Timeout,
        )
    })?
    .map_err(|e| {
        fail(
            &session,
            "Не удалось подготовить вход Apple",
            Failure::from_report(&e),
        )
    })?;
    session.diagnostic("AUTH_ANISETTE_PROVISION");
    tokio::time::timeout(
        std::time::Duration::from_secs(90),
        account
            .anisette_generator
            .get_anisette_data(account.grandslam_client.clone()),
    )
    .await
    .map_err(|_| {
        fail(
            &session,
            "Не удалось подготовить anisette",
            Failure::Timeout,
        )
    })?
    .map_err(|e| {
        fail(
            &session,
            "Сбой подготовки anisette",
            Failure::from_report(&e),
        )
    })?;
    session.diagnostic("AUTH_APPLE_LOGIN");
    let result = account.login(&config.password, callback).await;
    config.password.zeroize();
    result.map_err(|e| fail(&session, "Вход Apple не завершён", Failure::from_report(&e)))?;
    session.diagnostic("AUTH_APPLE_OK");
    let mut developer = DeveloperSession::from_account(&mut account)
        .await
        .map_err(|e| {
            fail(
                &session,
                "Apple не открыл developer-сессию",
                Failure::from_report(&e),
            )
        })?;
    session.diagnostic("AUTH_DEVELOPER_OK");
    drop(account);
    let teams = developer.list_teams().await.map_err(|e| {
        fail(
            &session,
            "Не удалось получить команды Apple Developer",
            Failure::from_report(&e),
        )
    })?;
    let team = if teams.len() == 1 {
        teams[0].clone()
    } else {
        if teams.is_empty() {
            return Err("Apple не предоставил Personal Team. Проверь возраст, подтверждение email и условия Apple Developer.".into());
        }
        let a = session.answer("team", json!({"choices": teams.iter().map(|t| json!({"id":t.team_id,"name":t.name})).collect::<Vec<_>>()})).await?;
        teams
            .into_iter()
            .find(|t| Some(t.team_id.as_str()) == a["value"].as_str())
            .ok_or("Команда не выбрана")?
    };
    developer
        .ensure_device_registered(&team, "SideRelay target", udid, None)
        .await
        .map_err(|e| {
            fail(
                &session,
                "Apple не зарегистрировал целевое устройство",
                Failure::from_report(&e),
            )
        })?;
    let cert_session = session.clone();
    let cert_callback: MaxCertsCallbackBox = Box::new(move |certs| {
        let s = cert_session.clone();
        Box::pin(async move {
            let choices = certs.iter().filter_map(|c|c.certificate_id.as_ref().map(|id|json!({"id":id,"name":c.machine_name.as_deref().or(c.name.as_deref()).unwrap_or("Development certificate")}))).collect::<Vec<_>>();
            let answer = s
                .answer("certificate", json!({"choices":choices}))
                .await
                .map_err(|_| rootcause::report!("Certificate replacement cancelled"))?;
            let id = answer["value"]
                .as_str()
                .ok_or_else(|| rootcause::report!("No certificate selected"))?;
            if answer["action"] != "revoke"
                || !certs
                    .iter()
                    .any(|c| c.certificate_id.as_deref() == Some(id))
            {
                return Err(rootcause::report!("Certificate replacement not confirmed"));
            }
            Ok(Some(vec![id.to_string()]))
        })
    });
    let mut signer = SideloaderBuilder::<MaxCertsCallbackBox, ExtensionsBehaviorCallbackBox>::new(
        developer,
        config.email.trim().into(),
    )
    .storage(Box::new(InMemoryStorage::new()))
    .machine_name("SideRelay · temporary session".into())
    .max_certs_behavior(MaxCertsBehavior::Prompt(cert_callback))
    .extensions_behavior(ExtensionsBehaviorSelection::Fixed(
        ExtensionsBehavior::RegisterAll,
    ))
    .build();
    let progress = session.clone();
    let (signed, _) = signer
        .sign_app(
            config.ipa_path.clone(),
            Some(team),
            false,
            Some(move |p: f32| {
                progress.progress(
                    "signing",
                    0.25 + p.clamp(0.0, 1.0) * 0.49,
                    "Регистрируем App ID, получаем профиль и подписываем IPA…",
                );
                std::future::ready(())
            }),
            None,
            Some(udid),
        )
        .await
        .map_err(|e| {
            fail(
                &session,
                "Подпись не завершена: проверь лимиты сертификатов, App ID и возможности IPA",
                Failure::from_report(&e),
            )
        })?;
    Ok(signed)
}

fn fail(session: &Session, phase: &str, failure: Failure) -> String {
    session.diagnostic(&failure.code());
    failure.message(phase)
}
