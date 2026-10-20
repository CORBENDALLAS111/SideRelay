import Foundation
import Observation
import UIKit
import Darwin

struct RelayChoice: Identifiable {
    let id: String
    let name: String
}
struct RelayChallenge: Identifiable {
    let id: String
    let kind: String
    let data: [String: Any]
    var choices: [RelayChoice] {
        (data["choices"] as? [[String: Any]] ?? []).compactMap { value in
            guard let id = value["id"] as? String else { return nil }
            return RelayChoice(id: id, name: value["name"] as? String ?? id)
        }
    }
}

@MainActor @Observable
final class RelayModel: NSObject, NetServiceDelegate, NetServiceBrowserDelegate {
    var targetIP = ""
    var email = ""
    var password = ""
    var anisette = "https://ani.jkcoxson.com"
    var consent = false
    private(set) var fileName = ""
    private(set) var fileBytes: Int64 = 0
    private(set) var busy = false
    private(set) var importing = false
    private(set) var message = "Выбери IPA и укажи второй iPhone."
    private(set) var progress = 0.0
    private(set) var stage = "ready"
    private(set) var pin = ""
    private(set) var installed = false
    var challenge: RelayChallenge?

    @ObservationIgnored private var ipa: URL?
    @ObservationIgnored private var session: UInt64 = 0
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var advertisement: NetService?
    @ObservationIgnored private var browser: NetServiceBrowser?
    @ObservationIgnored private var services: [NetService] = []

    override init() {
        super.init()
        // Only our UUID-named scratch files, inside this app's own sandbox.
        let root = FileManager.default.temporaryDirectory
        for path in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let name = path.lastPathComponent
            let stem = name.hasSuffix("_extracted") ? String(name.dropLast("_extracted".count)) : path.deletingPathExtension().lastPathComponent
            if stem.hasPrefix("SideRelay-"), UUID(uuidString: String(stem.dropFirst("SideRelay-".count))) != nil {
                try? FileManager.default.removeItem(at: path)
            }
        }
    }
    var canStart: Bool { ipa != nil && !busy && !importing && !targetIP.isEmpty && !email.isEmpty && !password.isEmpty && consent }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: fileBytes, countStyle: .file) }

    func importIPA(_ url: URL) {
        guard !busy && !importing else { return }
        importing = true
        message = "Импортируем IPA на этот iPhone…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard url.pathExtension.lowercased() == "ipa" else { throw ImportError.invalid }
                    var fileError: NSError?
                    var result: Result<(URL, Int64), Error> = .failure(ImportError.invalid)
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &fileError) { source in
                        do {
                            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size > 0 && size <= 128 * 1024 * 1024 else { throw ImportError.size }
                            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("SideRelay-\(UUID().uuidString).ipa")
                            do {
                                try FileManager.default.copyItem(at: source, to: copy)
                                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path)
                                var attributes = URLResourceValues()
                                attributes.isExcludedFromBackup = true
                                var excluded = copy
                                try excluded.setResourceValues(attributes)
                                result = .success((copy, Int64(size)))
                            } catch {
                                try? FileManager.default.removeItem(at: copy)
                                throw error
                            }
                        } catch { result = .failure(error) }
                    }
                    if let fileError { throw fileError }
                    return try result.get()
                }.value
                if let ipa { try? FileManager.default.removeItem(at: ipa) }
                ipa = result.0
                fileName = url.lastPathComponent
                fileBytes = result.1
                installed = false
                message = "IPA готов. Сопряжение начнётся после нажатия кнопки."
            } catch {
                message = "Не удалось импортировать IPA. Нужен доступный файл .ipa размером до 128 МБ. Для файла в iCloud дождись загрузки."
            }
            importing = false
        }
    }
    private enum ImportError: Error { case invalid, size }

    func start() {
        guard canStart, let ipa else { return }
        let values: [String: Any] = ["target_ip":targetIP.trimmingCharacters(in: .whitespacesAndNewlines), "ipa_path":ipa.path, "email":email.trimmingCharacters(in: .whitespacesAndNewlines), "password":password, "anisette":anisette.trimmingCharacters(in: .whitespacesAndNewlines)]
        guard let data = try? JSONSerialization.data(withJSONObject: values), let json = String(data: data, encoding: .utf8) else { return }
        session = json.withCString { relay_start($0) }
        password = ""
        guard session != 0 else { message = "Не удалось создать сессию. Заверши предыдущую операцию и попробуй снова."; return }
        busy = true
        installed = false
        pin = ""
        progress = 0
        stage = "pairing"
        UIApplication.shared.isIdleTimerDisabled = true
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.session != 0 else { return }
                while let raw = relay_poll(self.session) {
                    let data = Data(String(cString: raw).utf8)
                    relay_string_free(raw)
                    if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.receive(value) }
                    if self.session == 0 { return }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    func cancel() {
        guard session != 0 else { return }
        stopNetworking()
        challenge = nil
        pin = ""
        message = "Закрываем сессию…"
        relay_cancel(session)
    }
    func answer(_ action: String, value: Any = "") {
        guard let challenge else { return }
        send(["token":challenge.id,"action":action,"value":value])
        self.challenge = nil
    }
    func reportPickerError() { message = "Файл не выбран или недоступен. Попробуй открыть его из «Файлов»." }
    private func send(_ object: [String: Any]) {
        guard session != 0, let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data:data, encoding:.utf8) else { return }
        json.withCString { relay_reply(session, $0) }
    }
    private func receive(_ value: [String: Any]) {
        switch value["type"] as? String {
        case "progress":
            progress = value["progress"] as? Double ?? progress
            message = value["message"] as? String ?? message
            stage = value["stage"] as? String ?? stage
        case "advertise":
            guard let port = value["port"] as? Int, let name = value["name"] as? String, let pairs = value["txt"] as? [[String]] else { return }
            var txt: [String:Data] = [:]
            for pair in pairs where pair.count == 2 { txt[pair[0]] = Data(pair[1].utf8) }
            advertisement?.stop()
            let service = NetService(domain:"local.", type:"_remotepairing-pairable-host._tcp.", name:name, port:Int32(port))
            service.delegate = self
            service.setTXTRecord(NetService.data(fromTXTRecord:txt))
            advertisement = service
            service.publish()
        case "pin": pin = value["pin"] as? String ?? ""
        case "paired":
            pin = ""
            advertisement?.stop()
            advertisement = nil
            message = "Код принят. Ищем защищённую службу второго iPhone…"
        case "browse":
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType:"_remotepairing._tcp.", inDomain:"local.")
        case "challenge":
            guard let token = value["token"] as? String, let kind = value["kind"] as? String else { return }
            challenge = RelayChallenge(id:token, kind:kind, data:value["data"] as? [String:Any] ?? [:])
            if kind == "two_factor" { message = "Apple запросил подтверждение входа." }
        case "installed":
            installed = true
            progress = 1
            stage = "installed"
            message = value["message"] as? String ?? "Установка подтверждена iOS."
        case "error":
            installed = false
            stage = "error"
            message = value["message"] as? String ?? "Операция не завершена."
        case "finished": finish()
        default: break
        }
    }
    private func finish() {
        stopNetworking()
        relay_release(session)
        session = 0
        polling?.cancel()
        polling = nil
        busy = false
        pin = ""
        password = ""
        challenge = nil
        // Rust deletes this copy and its extracted bundle, including on cancellation.
        // A crash is handled by the narrowly scoped startup cleanup.
        ipa = nil
        fileName = ""
        fileBytes = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func stopNetworking() {
        advertisement?.stop(); advertisement = nil
        browser?.stop(); browser = nil
        for service in services { service.stop() }
        services.removeAll()
    }
    func netService(_ sender: NetService, didNotPublish errorDict: [String:NSNumber]) {
        message = "Не удалось объявить SideRelay в сети. Разреши «Локальная сеть» для SideRelay и проверь Wi-Fi."
        relay_cancel(session)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout:10)
    }
    func netServiceDidResolveAddress(_ sender: NetService) { reportEndpoint(sender) }
    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) { reportEndpoint(sender) }
    private func reportEndpoint(_ service: NetService) {
        guard service.port > 0, let txtData = service.txtRecordData() else { return }
        let txt = NetService.dictionary(fromTXTRecord:txtData)
        guard let id = txt["identifier"].flatMap({String(data:$0, encoding:.utf8)}), let tag = txt["authTag"].flatMap({String(data:$0, encoding:.utf8)}) else { return }
        for address in service.addresses ?? [] {
            let host: String? = address.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress, bytes.count >= MemoryLayout<sockaddr_in>.size else { return nil }
                let socket = base.assumingMemoryBound(to:sockaddr.self)
                guard socket.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                var buffer = [CChar](repeating:0, count:Int(NI_MAXHOST))
                guard getnameinfo(socket, socklen_t(address.count), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                return String(cString:buffer)
            }
            if let host { send(["type":"endpoint","ip":host,"port":service.port,"identifier":id,"authTag":tag]) }
        }
    }
}
