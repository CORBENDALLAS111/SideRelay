//! Only structured status codes cross the FFI boundary. Never format upstream reports:
//! their attachments may contain Apple tokens, identifiers or response bodies.
use isideload::SideloadError;

#[derive(Debug, PartialEq)]
pub enum Failure {
    Apple(i64),
    Developer(i64),
    Http(u16),
    Timeout,
    Network,
    Unknown,
}

impl Failure {
    pub fn from_report(report: &rootcause::Report) -> Self {
        for cause in report.iter_reports() {
            if let Some(error) = cause.downcast_current_context::<SideloadError>() {
                match error {
                    SideloadError::AuthWithMessage(code, _) => return Self::Apple(*code),
                    SideloadError::DeveloperError(code, _) => return Self::Developer(*code),
                    _ => {}
                }
            }
            if let Some(error) = cause.downcast_current_context::<reqwest::Error>() {
                return Self::from_http(error);
            }
            let mut source = cause.current_context_error_source();
            while let Some(error) = source {
                if let Some(error) = error.downcast_ref::<reqwest::Error>() {
                    return Self::from_http(error);
                }
                source = error.source();
            }
        }
        Self::Unknown
    }

    fn from_http(error: &reqwest::Error) -> Self {
        if let Some(status) = error.status() {
            Self::Http(status.as_u16())
        } else if error.is_timeout() {
            Self::Timeout
        } else if error.is_connect() || error.is_request() {
            Self::Network
        } else {
            Self::Unknown
        }
    }

    pub fn code(&self) -> String {
        fn number(code: i64) -> String {
            if code < 0 {
                format!("NEG_{}", code.unsigned_abs())
            } else {
                code.to_string()
            }
        }
        match self {
            Self::Apple(code) => format!("APPLE_AUTH_{}", number(*code)),
            Self::Developer(code) => format!("APPLE_DEV_{}", number(*code)),
            Self::Http(code) => format!("HTTP_{code}"),
            Self::Timeout => "TIMEOUT".into(),
            Self::Network => "NETWORK".into(),
            Self::Unknown => "UNKNOWN".into(),
        }
    }

    pub fn message(&self, phase: &str) -> String {
        let advice = match self {
            Self::Apple(-20101 | -22406) => {
                "Apple отклонил Apple ID или пароль. Проверь вход на account.apple.com. Нужен обычный пароль аккаунта, не пароль приложения."
            }
            Self::Apple(-21669) => {
                "Код подтверждения неверный или истёк. Запроси новый код и введи его без пробелов."
            }
            Self::Apple(-80045) => {
                "Apple отклонил идентичность anisette. Выбери Windows ADI в настройках SideRelay и повтори позже. Это не означает, что пароль неверный."
            }
            Self::Developer(2160) => {
                "Подтверди email на account.apple.com, затем повтори установку."
            }
            Self::Developer(1102) => {
                "Apple запретил разработку для этого аккаунта из-за возрастных ограничений. Используй подходящий аккаунт."
            }
            Self::Developer(9120) => {
                "Исчерпан недельный лимит App ID. Дождись его обновления или используй другой аккаунт."
            }
            Self::Http(429) => {
                "Слишком много запросов. Подожди перед новой попыткой; повторный ввод пароля сейчас не поможет."
            }
            Self::Http(500..=599) => {
                "Сервис временно недоступен. Повтори позже. Для anisette можно выбрать другой Windows ADI сервер в настройках."
            }
            Self::Http(401 | 403) => {
                "Сервис отказал в запросе. Проверь вход и ограничения аккаунта на account.apple.com; для anisette выбери другой сервер."
            }
            Self::Timeout | Self::Network => {
                "Проверь интернет и доступ SideRelay к сети. VPN, фильтр DNS или роутер могут блокировать Apple либо anisette."
            }
            _ => {
                "Открой account.apple.com и developer.apple.com: проверь email, доступ к аккаунту и непринятые условия. Скопируй диагностику SideRelay, если ошибка повторяется."
            }
        };
        format!("{phase}. {advice} Код: {}.", self.code())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn apple_error_keeps_only_code_even_with_sensitive_attachments() {
        let report: rootcause::Report = rootcause::report!(SideloadError::AuthWithMessage(
            -80045,
            "private@example.com password token 123456".into()
        ))
        .attach("secret response body")
        .context("login request")
        .into();
        let failure = Failure::from_report(&report);
        assert_eq!(failure, Failure::Apple(-80045));
        assert_eq!(failure.code(), "APPLE_AUTH_NEG_80045");
        let public = failure.message("Вход");
        for secret in [
            "private@example.com",
            "password",
            "token",
            "123456",
            "secret response body",
        ] {
            assert!(!public.contains(secret));
        }
    }
    #[test]
    fn developer_error_is_not_misreported_as_bad_password() {
        let report: rootcause::Report =
            rootcause::report!(SideloadError::DeveloperError(2160, "private email".into())).into();
        let failure = Failure::from_report(&report);
        assert_eq!(failure, Failure::Developer(2160));
        assert!(failure.message("Developer").contains("Подтверди email"));
    }
    #[test]
    fn unknown_errors_never_echo_upstream_text() {
        let report = rootcause::report!("URL with secret account and token");
        assert_eq!(Failure::from_report(&report), Failure::Unknown);
        assert!(
            !Failure::from_report(&report)
                .message("Вход")
                .contains("secret")
        );
    }
}
