import SwiftUI

struct LicenseView: View {
    var body: some View {
        ScrollView {
            Text(notices).font(.caption.monospaced()).textSelection(.enabled).padding(20)
        }.navigationTitle("Лицензии")
    }
    private var notices: String {
        guard let path = Bundle.main.url(forResource:"ThirdPartyNotices",withExtension:"txt"), let text = try? String(contentsOf:path,encoding:.utf8) else { return "Тексты лицензий доступны в исходном репозитории и пакетах Cargo." }
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
                        Text("Это нужное устройство?").font(.title.bold())
                        Text(challenge.data["name"] as? String ?? "Устройство").font(.title2)
                        Text("iOS \(challenge.data["version"] as? String ?? "—")")
                        Text("UDID: \(challenge.data["udid"] as? String ?? "—")").font(.caption.monospaced()).textSelection(.enabled)
                        Text("Установить: \(challenge.data["app"] as? String ?? "IPA")").font(.headline)
                        primary("Подписать и установить") { model.answer("confirm") }
                    } else if challenge.kind == "two_factor" {
                        Text("Подтверди вход в Apple").font(.title.bold())
                        Text(challenge.data["hint"] as? String ?? "Введи код с доверенного устройства или из SMS.").foregroundStyle(.secondary)
                        TextField("Код подтверждения",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode).font(.title.monospaced()).textFieldStyle(.roundedBorder)
                        primary("Отправить код") { model.answer("code", value:code); code = "" }.disabled(code.count < 4 || challenge.data["unknown"] as? Bool == true)
                        Button("Отправить код на доверенные устройства") { model.answer("devices") }
                        ForEach(numbers) { number in Button("SMS: \(number.name)") { model.answer("sms",value:Int(number.id) ?? 0) } }
                        Button("Повторить отправку") { model.answer("resend") }
                    } else if challenge.kind == "certificate" {
                        Text("Лимит сертификатов").font(.title.bold())
                        Text("Apple не даёт создать ещё один сертификат. Отзыв существующего может отключить твой SideStore, LiveContainer и другие приложения, подписанные им. Можно отменить и использовать другой Apple ID.").foregroundStyle(.orange)
                        ForEach(challenge.choices) { choice in
                            Button(role:.destructive) { pendingCertificate = choice } label: {
                                Text("Отозвать «\(choice.name)»").frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.bordered)
                        }
                    } else if challenge.kind == "team" {
                        Text("Команда разработчика").font(.title.bold())
                        ForEach(challenge.choices) { choice in primary(choice.name) { model.answer("select",value:choice.id) } }
                    }
                    Button("Отменить установку",role:.cancel) { model.cancel(reason:"Установка отменена.") }.frame(maxWidth:.infinity)
                }.padding(24)
            }.navigationTitle("SideRelay").navigationBarTitleDisplayMode(.inline)
            .tint(relayTint)
            .confirmationDialog("Отозвать сертификат? Подписанные им приложения могут перестать открываться.",isPresented:Binding(get:{pendingCertificate != nil},set:{if !$0 { pendingCertificate = nil }}),titleVisibility:.visible) {
                if let choice = pendingCertificate { Button("Отозвать и продолжить",role:.destructive) { model.answer("revoke",value:choice.id); pendingCertificate = nil } }
                Button("Назад",role:.cancel) { pendingCertificate = nil }
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
