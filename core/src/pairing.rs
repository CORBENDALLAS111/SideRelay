//! Device-initiated pairing. Accept both address families advertised by Bonjour.
use crate::Session;
use idevice::{
    IdeviceError,
    remote_pairing::{
        PairableHost, PairableHostInfo, PeerDevice, RpPairingFile, RpPairingSocket,
        RpPairingSocketProvider,
    },
};
use serde::Serialize;
use serde_json::json;
use socket2::{Domain, Protocol, Socket, Type};
use std::{
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    pin::Pin,
    time::Duration,
};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::Notify,
};

fn listener() -> std::io::Result<(TcpListener, bool)> {
    // Bonjour publishes both A and AAAA records. An IPv4-only socket leaves an
    // iPhone selecting the IPv6 endpoint unable to reach the PIN callback.
    let dual = || -> std::io::Result<TcpListener> {
        let socket = Socket::new(Domain::IPV6, Type::STREAM, Some(Protocol::TCP))?;
        socket.set_only_v6(false)?;
        socket.set_nonblocking(true)?;
        socket.bind(&SocketAddr::new(IpAddr::V6(Ipv6Addr::UNSPECIFIED), 0).into())?;
        socket.listen(8)?;
        TcpListener::from_std(socket.into())
    };
    if let Ok(listener) = dual() {
        return Ok((listener, true));
    }
    let socket = Socket::new(Domain::IPV4, Type::STREAM, Some(Protocol::TCP))?;
    socket.set_nonblocking(true)?;
    socket.bind(&SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0).into())?;
    socket.listen(8)?;
    Ok((TcpListener::from_std(socket.into())?, false))
}

fn eligible_peer(expected: IpAddr, actual: IpAddr) -> bool {
    match actual {
        IpAddr::V4(_) => actual == expected,
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4) == expected,
            // A peer's IPv6 address cannot be compared with its typed IPv4.
            // Trust is established by SRP/PIN, then mDNS authTag, pair-verify,
            // the requested IPv4 endpoint and the explicit device confirmation.
            None => !v6.is_loopback() && !v6.is_unspecified() && !v6.is_multicast(),
        },
    }
}

struct ObservedSocket<'a> {
    socket: RpPairingSocket<TcpStream>,
    session: &'a Session,
}
impl std::fmt::Debug for ObservedSocket<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("PairingSocket")
    }
}
impl RpPairingSocketProvider for ObservedSocket<'_> {
    fn send_plain(
        &mut self,
        value: impl Serialize,
        seq: usize,
    ) -> Pin<Box<dyn Future<Output = Result<(), IdeviceError>> + Send + '_>> {
        self.session.diagnostic("PAIR_REPLY_OUT");
        self.socket.send_plain(value, seq)
    }
    fn send_encrypted(
        &mut self,
        value: Vec<u8>,
        seq: usize,
    ) -> Pin<Box<dyn Future<Output = Result<(), IdeviceError>> + Send + '_>> {
        self.socket.send_encrypted(value, seq)
    }
    fn recv_plain(
        &mut self,
    ) -> Pin<Box<dyn Future<Output = Result<plist::Value, IdeviceError>> + Send + '_>> {
        let session = self.session;
        let next = self.socket.recv_plain();
        Box::pin(async move {
            let value = next.await?;
            session.diagnostic("PAIR_MESSAGE_IN");
            Ok(value)
        })
    }
    fn serialize_bytes(b: &[u8]) -> plist::Value {
        RpPairingSocket::<TcpStream>::serialize_bytes(b)
    }
    fn deserialize_bytes(v: plist::Value) -> Option<Vec<u8>> {
        RpPairingSocket::<TcpStream>::deserialize_bytes(v)
    }
}

pub async fn pair(ip: IpAddr, session: &Session) -> Result<(RpPairingFile, PeerDevice), String> {
    let identity = format!("SideRelay-{}", uuid::Uuid::new_v4());
    let mut record = RpPairingFile::generate(&identity);
    let mut info = PairableHostInfo::generate("SideRelay", "Mac17,7");
    info.identifier = record.identifier().to_string();
    let (listener, dual_stack) = listener().map_err(|_| "Не удалось открыть порт сопряжения")?;
    session.diagnostic(if dual_stack {
        "PAIR_LISTEN_DUAL"
    } else {
        "PAIR_LISTEN_IPV4"
    });
    let port = listener
        .local_addr()
        .map_err(|_| "Не удалось получить порт")?
        .port();
    session.emit(json!({"type":"advertise","name":record.identifier(),"port":port,"txt":info.mdns_txt_records(record.identifier())}));
    session.progress("pairing", 0.05, "Выбери SideRelay на целевом устройстве");
    tokio::time::timeout(Duration::from_secs(240), async {
        loop {
            let (socket, address) = listener.accept().await.map_err(|_| "Ошибка приёма соединения")?;
            if !eligible_peer(ip, address.ip()) {
                session.diagnostic("PAIR_ADDRESS_MISMATCH");
                session.progress("pairing", 0.05, "Проверь IP целевого устройства");
                continue;
            }
            session.diagnostic(if address.is_ipv6() { "PAIR_TCP_IPV6" } else { "PAIR_TCP_IPV4" });
            session.progress("handshake", 0.07, "Устройство подключено. Создаём код…");
            let pin_ready = Notify::new();
            let mut host = PairableHost::new(ObservedSocket { socket: RpPairingSocket::new_device(socket), session }, info.clone());
            let pin_signal = &pin_ready;
            let operation = host.accept(&mut record, |pin| async move {
                session.diagnostic("PAIR_PIN_READY");
                session.emit(json!({"type":"pin","pin":pin}));
                pin_signal.notify_one();
            });
            tokio::pin!(operation);
            // Discovery/probe sockets must not occupy the single accept slot
            // for 3 minutes. Retry preflight/failed sockets without ending the UI.
            let result = tokio::select! {
                result = &mut operation => Some(result),
                _ = pin_ready.notified() => {
                    tokio::time::timeout(Duration::from_secs(180), &mut operation).await.ok()
                }
                _ = tokio::time::sleep(Duration::from_secs(12)) => None,
            };
            match result {
                Some(Ok(peer)) => {
                    session.diagnostic("PAIR_VERIFIED");
                    session.emit(json!({"type":"paired"}));
                    return Ok(peer);
                }
                Some(Err(error)) => session.diagnostic(&format!("PAIR_ERROR_{}_{}", error.code(), error.sub_code())),
                None => session.diagnostic("PAIR_HANDSHAKE_TIMEOUT"),
            }
            session.emit(json!({"type":"pin_clear"}));
            session.progress("pairing", 0.05, "Выбери SideRelay ещё раз на целевом устройстве");
        }
    }).await.map_err(|_| "Код не получен. Проверь IP и локальную сеть. В настройках выбери SideRelay заново; подробности — в диагностике.".to_string())?
    .map(|peer| (record, peer))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn maps_ipv4_and_accepts_ipv6_onboarding() {
        let expected = "192.168.1.42".parse().unwrap();
        assert!(eligible_peer(
            expected,
            "::ffff:192.168.1.42".parse().unwrap()
        ));
        assert!(!eligible_peer(
            expected,
            "::ffff:192.168.1.43".parse().unwrap()
        ));
        assert!(eligible_peer(expected, "fe80::1234".parse().unwrap()));
        assert!(eligible_peer(expected, "fd00::1234".parse().unwrap()));
        assert!(!eligible_peer(expected, "::1".parse().unwrap()));
    }
    #[tokio::test]
    async fn same_listener_accepts_both_address_families() {
        let (listener, dual) = listener().unwrap();
        assert!(dual);
        let port = listener.local_addr().unwrap().port();
        let _v4 = TcpStream::connect((Ipv4Addr::LOCALHOST, port))
            .await
            .unwrap();
        let (v4, _) = listener.accept().await.unwrap();
        drop(v4);
        let _v6 = TcpStream::connect((Ipv6Addr::LOCALHOST, port))
            .await
            .unwrap();
        let (v6, _) = listener.accept().await.unwrap();
        drop(v6);
    }
    #[tokio::test]
    async fn probe_socket_does_not_block_pin_on_next_connection() {
        use std::sync::{Arc, Mutex};
        use tokio::sync::mpsc;
        let (sender, receiver) = mpsc::unbounded_channel();
        let session = Arc::new(Session {
            events: Mutex::default(),
            sender,
            input: tokio::sync::Mutex::new(receiver),
            cancel: Notify::new(),
        });
        let worker = session.clone();
        let task = tokio::spawn(async move { pair("127.0.0.1".parse().unwrap(), &worker).await });
        let port = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let port = session
                    .events
                    .lock()
                    .unwrap()
                    .iter()
                    .find(|v| v["type"] == "advertise")
                    .and_then(|v| v["port"].as_u64());
                if let Some(port) = port {
                    break port as u16;
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .unwrap();
        // A discovery probe connects, then closes before the protocol starts.
        let probe = TcpStream::connect((Ipv4Addr::LOCALHOST, port))
            .await
            .unwrap();
        drop(probe);
        let stream = TcpStream::connect((Ipv4Addr::LOCALHOST, port))
            .await
            .unwrap();
        let mut client = RpPairingSocket::new(stream);
        client.send_plain(json!({"request":{"_0":{"handshake":{"_0":{"hostOptions":{"attemptPairVerify":false}}}}}}),0).await.unwrap();
        let response = tokio::time::timeout(Duration::from_secs(5), client.recv_plain())
            .await
            .unwrap()
            .unwrap();
        assert!(response.as_dictionary().unwrap().contains_key("response"));
        let m1 = RpPairingSocket::<TcpStream>::serialize_bytes(&[6, 1, 1]);
        client.send_plain(json!({"event":{"_0":{"pairingData":{"_0":{"data":m1,"kind":"setupManualPairing","startNewSession":true}}}}}),1).await.unwrap();
        let pin = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let pin = session
                    .events
                    .lock()
                    .unwrap()
                    .iter()
                    .find(|v| v["type"] == "pin")
                    .and_then(|v| v["pin"].as_str())
                    .map(str::to_string);
                if let Some(pin) = pin {
                    break pin;
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .unwrap();
        assert_eq!(pin.len(), 6);
        assert!(pin.bytes().all(|b| b.is_ascii_digit()));
        task.abort();
        let _ = task.await;
    }
}
