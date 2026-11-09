import SwiftUI

struct LicenseView: View {
    var body: some View {
        ScrollView {
            Text(notices).font(.caption.monospaced()).textSelection(.enabled).padding(20)
        }.navigationTitle(L("Лицензии"))
    }
    private var notices: String {
        guard let path = Bundle.main.url(forResource:"ThirdPartyNotices",withExtension:"txt"), let text = try? String(contentsOf:path,encoding:.utf8) else { return L("Тексты лицензий доступны в исходном репозитории и пакетах Cargo.") }
        return text
    }
}

struct ChallengeView: View {
    let model: RelayModel
    let challenge: RelayChallenge
    @State private var code = ""
    @State private var pendingCertificate: RelayChoice?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    if challenge.kind == "device" {
                        Text(L("Это нужное устройство?")).font(.title.bold())
                        Text(challenge.data["name"] as? String ?? L("Устройство")).font(.title2)
                        Text("iOS \(challenge.data["version"] as? String ?? "—")")
                        Text("UDID: \(challenge.data["udid"] as? String ?? "—")").font(.caption.monospaced()).textSelection(.enabled)
                        Text(L("Установить: %@",challenge.data["app"] as? String ?? "IPA")).font(.headline)
                        primary(L("Подписать и установить")) { model.answer("confirm") }
                    } else if challenge.kind == "two_factor" {
                        Text(L("Подтверди вход в Apple")).font(.title.bold())
                        Text((challenge.data["hint"] as? String).map(RelayText.core) ?? L("Введи код с доверенного устройства или из SMS.")).foregroundStyle(.secondary)
                        TextField(L("Код подтверждения"),text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode).font(.title.monospaced()).textFieldStyle(.roundedBorder)
                        primary(L("Отправить код")) { model.answer("code", value:code); code = "" }.disabled(code.count < 4 || challenge.data["unknown"] as? Bool == true)
                        Button(L("Отправить код на доверенные устройства")) { model.answer("devices") }
                        ForEach(numbers) { number in Button("SMS: \(number.name)") { model.answer("sms",value:Int(number.id) ?? 0) } }
                        Button(L("Повторить отправку")) { model.answer("resend") }
                    } else if challenge.kind == "certificate" {
                        Text(L("Лимит сертификатов")).font(.title.bold())
                        Text(L("Apple не даёт создать ещё один сертификат. Отзыв существующего может отключить твой SideStore, LiveContainer и другие приложения, подписанные им. Можно отменить и использовать другой Apple ID.")).foregroundStyle(.secondary)
                        ForEach(challenge.choices) { choice in
                            Button(role:.destructive) { pendingCertificate = choice } label: {
                                Text(L("Отозвать «%@»",choice.name)).frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.bordered)
                        }
                    } else if challenge.kind == "team" {
                        Text(L("Команда разработчика")).font(.title.bold())
                        ForEach(challenge.choices) { choice in primary(choice.name) { model.answer("select",value:choice.id) } }
                    }
                    Button(L("Отменить установку"),role:.cancel) { model.cancel(reason:L("Установка отменена.")) }.frame(maxWidth:.infinity)
                }.padding(24)
            }.navigationTitle("SideRelay").navigationBarTitleDisplayMode(.inline)
            .tint(relayTint)
            .confirmationDialog(L("Отозвать сертификат? Подписанные им приложения могут перестать открываться."),isPresented:Binding(get:{pendingCertificate != nil},set:{if !$0 { pendingCertificate = nil }}),titleVisibility:.visible) {
                if let choice = pendingCertificate { Button(L("Отозвать и продолжить"),role:.destructive) { model.answer("revoke",value:choice.id); pendingCertificate = nil } }
                Button(L("Назад"),role:.cancel) { pendingCertificate = nil }
            }
        }
    }
    private var numbers: [RelayChoice] {
        (challenge.data["numbers"] as? [[String:Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            return RelayChoice(id:String(id),name:item["numberWithDialCode"] as? String ?? "••\(item["lastTwoDigits"] as? String ?? "")")
        }
    }
    private func primary(_ title:String,action:@escaping ()->Void) -> some View {
        Button(action:action) { Text(title).frame(maxWidth:.infinity).padding(.vertical,6) }.buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large)
    }
}
