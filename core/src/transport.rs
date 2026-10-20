use crate::Session;
use idevice::{
    RsdService,
    lockdown::LockdownClient,
    remote_pairing::{
        PeerDevice, RemotePairingClient, RpPairingFile, RpPairingSocket,
        connect_tls_psk_tunnel_native,
    },
    rsd::RsdHandshake,
    tcp::{adapter::Adapter, handle::AdapterHandle},
};
use std::{
    net::{IpAddr, Ipv4Addr},
    time::Duration,
};
use tokio::net::TcpStream;

pub fn target_address(s: &str) -> Result<IpAddr, String> {
    let ip: Ipv4Addr = s
        .trim()
        .parse()
        .map_err(|_| "Введи IPv4 целевого устройства из настроек сети")?;
    if !ip.is_private() || ip.octets()[3] == 0 || ip.octets()[3] == 255 {
        return Err("Нужен локальный адрес целевого устройства (например, 192.168.1.42)".into());
    }
    Ok(IpAddr::V4(ip))
}
pub async fn pair(ip: IpAddr, session: &Session) -> Result<(RpPairingFile, PeerDevice), String> {
    crate::pairing::pair(ip, session).await
}

pub struct Link {
    pub handle: AdapterHandle,
    pub handshake: RsdHandshake,
}
impl Link {
    pub async fn connect(ip: IpAddr, port: u16, record: &RpPairingFile) -> Result<Self, String> {
        tokio::time::timeout(Duration::from_secs(40), async {
            let socket = TcpStream::connect((ip, port))
                .await
                .map_err(|_| "Нет соединения с целевым устройством")?;
            let mut client = RemotePairingClient::new(RpPairingSocket::new(socket), "SideRelay");
            client
                .attempt_pair_verify()
                .await
                .map_err(|_| "Устройство не начало проверку pairing")?;
            client
                .validate_pairing(&mut record.clone())
                .await
                .map_err(|_| "Устройство не подтвердило ключи pairing")?;
            let tunnel_port = client
                .create_tcp_listener()
                .await
                .map_err(|_| "Устройство отказало в создании туннеля")?;
            let tunnel = connect_tls_psk_tunnel_native(
                TcpStream::connect((ip, tunnel_port))
                    .await
                    .map_err(|_| "Туннель устройства недоступен")?,
                client.encryption_key(),
            )
            .await
            .map_err(|_| "Не удалось установить зашифрованный туннель")?;
            let parameters = tunnel.info.clone();
            let mut adapter = Adapter::new(
                Box::new(tunnel.into_inner()),
                parameters
                    .client_address
                    .parse()
                    .map_err(|_| "Неверный адрес туннеля")?,
                parameters
                    .server_address
                    .parse()
                    .map_err(|_| "Неверный адрес устройства")?,
            );
            adapter.set_mss((parameters.mtu as usize).saturating_sub(60).max(536));
            let mut handle = adapter.to_async_handle();
            let stream = handle
                .connect(parameters.server_rsd_port)
                .await
                .map_err(|_| "RSD-служба недоступна")?;
            let handshake = RsdHandshake::new(stream)
                .await
                .map_err(|_| "Устройство не предоставило список служб")?;
            Ok(Self { handle, handshake })
        })
        .await
        .map_err(|_| {
            "Подключение к службам целевого устройства заняло слишком много времени".to_string()
        })?
    }
    pub async fn identity(&mut self) -> Result<(String, String, String), String> {
        tokio::time::timeout(Duration::from_secs(20), async {
            let mut lockdown = LockdownClient::connect_rsd(&mut self.handle, &mut self.handshake)
                .await
                .map_err(|_| "Служба идентификации устройства недоступна")?;
            let mut values = Vec::new();
            for key in ["UniqueDeviceID", "DeviceName", "ProductVersion"] {
                let value = lockdown
                    .get_value(Some(key), None)
                    .await
                    .map_err(|_| "Устройство не сообщило данные устройства")?;
                values.push(
                    value
                        .as_string()
                        .ok_or("Неверный ответ устройства")?
                        .to_string(),
                );
            }
            if values[0].len() < 24 {
                return Err("Неверный UDID устройства".into());
            }
            Ok((values.remove(0), values.remove(0), values.remove(0)))
        })
        .await
        .map_err(|_| "Устройство не ответило на запрос идентификации".to_string())?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_local_target_addresses() {
        for ip in [
            "8.8.8.8",
            "127.0.0.1",
            "169.254.169.254",
            "0.0.0.0",
            "192.168.1.255",
            "attacker.example",
            "::1",
        ] {
            assert!(target_address(ip).is_err(), "{ip}");
        }
        assert!(target_address("192.168.1.42").is_ok());
        assert!(target_address("10.0.0.2").is_ok());
    }
}
