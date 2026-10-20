mod archive;
mod signing;
mod transport;

use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    ffi::{CStr, CString, c_char},
    path::PathBuf,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};
use tokio::{
    runtime::Runtime,
    sync::{Notify, mpsc},
};
use zeroize::Zeroize;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
fn sessions() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(Mutex::default)
}

pub struct Session {
    events: Mutex<VecDeque<Value>>,
    sender: mpsc::UnboundedSender<Value>,
    input: tokio::sync::Mutex<mpsc::UnboundedReceiver<Value>>,
    cancel: Notify,
}
impl Session {
    pub fn emit(&self, value: Value) {
        let mut queue = self.events.lock().unwrap();
        // Coalesce high-frequency progress; never discard a challenge or terminal event.
        if value["type"] == "progress" && queue.back().is_some_and(|v| v["type"] == "progress") {
            queue.pop_back();
        }
        queue.push_back(value);
    }
    pub fn progress(&self, stage: &str, value: f32, message: &str) {
        self.emit(json!({"type":"progress", "stage":stage,"progress":value,"message":message}));
    }
    pub async fn answer(&self, kind: &str, data: Value) -> Result<Value, String> {
        let token = uuid::Uuid::new_v4().to_string();
        self.emit(json!({"type":"challenge","kind":kind,"token":token,"data":data}));
        let mut rx = self.input.lock().await;
        tokio::time::timeout(std::time::Duration::from_secs(300), async {
            while let Some(v) = rx.recv().await {
                if v["token"] == token {
                    if v["action"] == "abort" {
                        return Err("Операция отменена".into());
                    }
                    return Ok(v);
                }
            }
            Err("Сессия закрыта".into())
        })
        .await
        .map_err(|_| "Время ожидания ответа истекло".to_string())?
    }
    pub async fn endpoint(
        &self,
        peer: &idevice::remote_pairing::PeerDevice,
        ip: std::net::IpAddr,
    ) -> Result<u16, String> {
        self.emit(json!({"type":"browse"}));
        let mut rx = self.input.lock().await;
        tokio::time::timeout(std::time::Duration::from_secs(60), async {
            while let Some(v) = rx.recv().await {
                if v["type"] != "endpoint" || v["ip"].as_str().and_then(|s|s.parse::<std::net::IpAddr>().ok()) != Some(ip) { continue; }
                if !idevice::remote_pairing::PeerDevice::validate_auth_tag(&peer.alt_irk, v["identifier"].as_str().unwrap_or(""), v["authTag"].as_str().unwrap_or("")) { continue; }
                if let Some(port) = v["port"].as_u64().filter(|p| *p > 0 && *p <= 65535) { return Ok(port as u16); }
            }
            Err("Поиск устройства прекращён".into())
        }).await.map_err(|_| "iPhone не объявил службу Remote Pairing. Проверь общую Wi-Fi сеть, разрешение «Локальная сеть» и отключи изоляцию клиентов на роутере.".to_string())?
    }
}

#[derive(Deserialize)]
pub struct Config {
    target_ip: String,
    ipa_path: PathBuf,
    email: String,
    password: String,
    anisette: String,
}
impl Drop for Config {
    fn drop(&mut self) {
        self.password.zeroize();
    }
}

async fn run(mut config: Config, session: Arc<Session>) -> Result<(), String> {
    let ip = transport::target_address(&config.target_ip)?;
    if config.email.trim().is_empty() || config.password.is_empty() {
        return Err("Введи Apple ID и пароль".into());
    }
    if !config.anisette.starts_with("https://") || config.anisette.len() > 512 {
        return Err("Anisette должен использовать HTTPS".into());
    }
    let _files = SessionFiles::new(&config.ipa_path)?;
    session.progress("validating", 0.01, "Проверяем IPA на этом iPhone…");
    let info = archive::inspect(&config.ipa_path)?;
    let (record, peer) = transport::pair(ip, &session).await?;
    let port = session.endpoint(&peer, ip).await?;
    let mut link = transport::Link::connect(ip, port, &record).await?;
    let (udid, name, version) = link.identity().await?;
    session.answer("device", json!({"name":name,"version":version,"udid":udid,"app":info.name,"bundle":info.bundle_id})).await?;
    let signed = signing::sign(&mut config, &udid, session.clone()).await?;
    // Reconnect after signing/2FA: an idle device tunnel may already have expired.
    drop(link);
    let mut link = transport::Link::connect(ip, port, &record).await?;
    let (verified, _, _) = link.identity().await?;
    if verified != udid {
        return Err("Идентичность второго iPhone изменилась. Установка остановлена.".into());
    }
    session.progress(
        "installing",
        0.75,
        "Передаём подписанное приложение второму iPhone…",
    );
    let progress = session.clone();
    tokio::time::timeout(std::time::Duration::from_secs(600),
        isideload::sideload::install::install_app_rsd(&mut link.handle, &mut link.handshake, &signed, move |p| {
            progress.progress("installing", 0.75 + p.min(100) as f32 * 0.0024, "Передача и установка через службы iOS…");
        })
    ).await.map_err(|_| "iOS не подтвердил установку за 10 минут. Приложение могло установиться: проверь второй телефон перед повтором.".to_string())?
    .map_err(|_| "iOS не подтвердил установку. Проверь Developer Mode, доверие разработчику, лимит трёх приложений и совместимость IPA.".to_string())?;
    session.emit(json!({"type":"installed","message":"iOS подтвердил установку. На втором телефоне при необходимости доверься разработчику в настройках VPN и управления устройством.","app":info.name}));
    Ok(())
}

// isideload extracts to <temp>/<IPA stem>_extracted. Accept only our UUID-named input.
// Never remove a caller-selected arbitrary directory. Drop also runs on cancellation/error.
struct SessionFiles {
    ipa: PathBuf,
    extracted: PathBuf,
}
impl SessionFiles {
    fn new(ipa: &std::path::Path) -> Result<Self, String> {
        let stem = ipa
            .file_stem()
            .and_then(|s| s.to_str())
            .ok_or("Неверное имя IPA")?;
        let id = stem
            .strip_prefix("SideRelay-")
            .ok_or("Импортируй IPA через приложение")?;
        uuid::Uuid::parse_str(id).map_err(|_| "Неверный идентификатор временного IPA")?;
        let temp = std::env::temp_dir()
            .canonicalize()
            .map_err(|_| "Нет временного каталога")?;
        let resolved = ipa.canonicalize().map_err(|_| "IPA недоступен")?;
        if resolved.parent() != Some(temp.as_path()) {
            return Err("IPA должен быть импортирован во временную папку SideRelay".into());
        }
        Ok(Self {
            ipa: resolved,
            extracted: temp.join(format!("{stem}_extracted")),
        })
    }
}
impl Drop for SessionFiles {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.ipa);
        let _ = std::fs::remove_dir_all(&self.extracted);
    }
}

/// # Safety
/// json must be a valid NUL-terminated UTF-8 string for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn relay_start(json: *const c_char) -> u64 {
    if json.is_null() {
        return 0;
    }
    let mut bytes = unsafe { CStr::from_ptr(json) }.to_bytes().to_vec();
    let config = serde_json::from_slice::<Config>(&bytes);
    bytes.zeroize();
    let Ok(config) = config else {
        return 0;
    };
    let rt = RUNTIME.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let _ = isideload::init();
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("Tokio runtime")
    });
    let mut map = sessions().lock().unwrap();
    if !map.is_empty() {
        return 0;
    }
    let (sender, receiver) = mpsc::unbounded_channel();
    let session = Arc::new(Session {
        events: Mutex::default(),
        sender,
        input: tokio::sync::Mutex::new(receiver),
        cancel: Notify::new(),
    });
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    map.insert(id, session.clone());
    rt.spawn(async move {
        let result = tokio::select! {
            result = run(config, session.clone()) => result,
            _ = session.cancel.notified() => Err("Сессия отменена. Если передача уже началась, проверь результат на втором iPhone.".into()),
            _ = tokio::time::sleep(std::time::Duration::from_secs(1200)) => Err("20 минут истекли. Сессия закрыта.".into()),
        };
        if let Err(message) = result { session.emit(json!({"type":"error","message":message})); }
        session.emit(json!({"type":"finished"}));
    });
    id
}

#[unsafe(no_mangle)]
pub extern "C" fn relay_poll(id: u64) -> *mut c_char {
    let map = sessions().lock().unwrap();
    let Some(session) = map.get(&id) else {
        return std::ptr::null_mut();
    };
    let Some(value) = session.events.lock().unwrap().pop_front() else {
        return std::ptr::null_mut();
    };
    CString::new(value.to_string()).unwrap().into_raw()
}

/// # Safety
/// json must be a valid NUL-terminated UTF-8 string during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn relay_reply(id: u64, json: *const c_char) {
    if json.is_null() {
        return;
    }
    let mut bytes = unsafe { CStr::from_ptr(json) }.to_bytes().to_vec();
    if let Ok(v) = serde_json::from_slice(&bytes) {
        if let Some(s) = sessions().lock().unwrap().get(&id) {
            let _ = s.sender.send(v);
        }
    }
    bytes.zeroize();
}
#[unsafe(no_mangle)]
pub extern "C" fn relay_cancel(id: u64) {
    if let Some(s) = sessions().lock().unwrap().get(&id) {
        s.cancel.notify_one();
    }
}
// Call after the "finished" event; releasing early also cancels the task.
#[unsafe(no_mangle)]
pub extern "C" fn relay_release(id: u64) {
    if let Some(s) = sessions().lock().unwrap().remove(&id) {
        s.cancel.notify_one();
    }
}
/// # Safety
/// ptr must be a string returned by relay_poll, and must be freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn relay_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { CString::from_raw(ptr) });
    }
}
