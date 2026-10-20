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
final class RelayModel: NSObject, @preconcurrency NetServiceDelegate, @preconcurrency NetServiceBrowserDelegate {
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
    private(set) var diagnostics: [String] = []
    var challenge: RelayChallenge?

    @ObservationIgnored private var ipa: URL?
    @ObservationIgnored private var session: UInt64 = 0
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var advertisement: NetService?
    @ObservationIgnored private var browser: NetServiceBrowser?
    @ObservationIgnored private var services: [NetService] = []
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var cancellationReason: String?

    override init() {
        super.init()
        // Only our UUID-named scratch files, inside this app's own sandbox.
        let root = FileManager.default.temporaryDirectory
        for path in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let name = path.lastPathComponent
            let filename = name.hasSuffix("_extracted") ? String(name.dropLast("_extracted".count)) : name
            let stem = (filename as NSString).deletingPathExtension
            if stem.hasPrefix("SideRelay-"), UUID(uuidString: String(stem.dropFirst("SideRelay-".count))) != nil {
                try? FileManager.default.removeItem(at: path)
            }
        }
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-preview"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let mode = ProcessInfo.processInfo.arguments[index + 1]
            fileName = "MyApp.ipa"; fileBytes = 24_000_000; targetIP = "192.168.1.42"
            email = "you@icloud.com"; consent = true
            if mode == "pin" { busy = true; stage = "pairing"; pin = "482916"; message = "Введи код на втором iPhone"; progress = 0.08 }
        }
        #endif
    }
    var canStart: Bool { ipa != nil && !busy && !importing && !targetIP.isEmpty && !email.isEmpty && !password.isEmpty && consent }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: fileBytes, countStyle: .file) }
    var hasAccount: Bool { !email.isEmpty && !password.isEmpty && consent }
    var statusTitle: String {
        if installed { return "Готово" }
        if !pin.isEmpty { return "Код сопряжения" }
        switch stage {
        case "pairing": return "Ждём второй iPhone"
        case "handshake": return "Создаём код"
        case "connecting": return "Проверяем iPhone"
        case "auth": return "Вход в Apple"
        case "signing": return "Подписываем"
        case "installing": return "Устанавливаем"
        case "error": return "Не получилось"
        default: return importing ? "Импортируем IPA" : "На другой iPhone"
        }
    }

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
        diagnostics = []
        cancellationReason = nil
        note("SESSION_START")
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
    func cancel(reason: String? = nil) {
        guard session != 0 else { return }
        cancellationReason = reason
        stopNetworking()
        challenge = nil
        pin = ""
        message = "Закрываем сессию…"
        relay_cancel(session)
    }
    func enterBackground() {
        guard busy, backgroundTask == .invalid else { return }
        note("APP_BACKGROUND")
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName:"SideRelay session") { [weak self] in
            Task { @MainActor in
                self?.cancel(reason:"iOS остановила фоновую сессию. Оставь SideRelay открытым и выбери его заново на втором iPhone.")
                self?.endBackground()
            }
        }
        if backgroundTask == .invalid { cancel(reason:"Не удалось продолжить в фоне. Оставь SideRelay открытым на первом iPhone.") }
    }
    func endBackground() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func copyDiagnostics() {
        UIPasteboard.general.string = (["SideRelay 0.2.0", "State: \(stage)"] + diagnostics).joined(separator:"\n")
    }
    private func note(_ code: String) {
        guard code.count <= 64, code.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")}) else { return }
        let time = Date().formatted(date:.omitted,time:.standard)
        diagnostics.append("\(time)  \(code)")
        if diagnostics.count > 40 { diagnostics.removeFirst(diagnostics.count - 40) }
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
        case "diagnostic": note(value["code"] as? String ?? "")
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
        case "pin": pin = value["pin"] as? String ?? ""; message = "Введи код на втором iPhone"
        case "pin_clear": pin = ""
        case "paired":
            pin = ""
            stage = "connecting"
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
            message = cancellationReason ?? (value["message"] as? String ?? "Операция не завершена.")
        case "finished": finish()
        default: break
        }
    }
    private func finish() {
        endBackground()
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
        note("BONJOUR_PUBLISH_FAILED")
        cancel(reason:"Разреши «Локальная сеть» для SideRelay в настройках iPhone.")
    }
    func netServiceDidPublish(_ sender: NetService) { note("BONJOUR_ADVERTISED") }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String:NSNumber]) { note("BONJOUR_BROWSE_FAILED") }
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
