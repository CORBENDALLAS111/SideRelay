import SwiftUI
import UniformTypeIdentifiers

private let relayAccent = Color(red:0.77, green:0.95, blue:0.48)

struct RelayView: View {
    @Bindable var model: RelayModel
    @State private var picking = false
    @State private var advanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:24) {
                    header
                    status
                    if !model.busy {
                        setup
                    } else {
                        pairing
                        Button(role:.destructive) { model.cancel() } label: {
                            Label("Завершить сессию", systemImage:"xmark.circle").frame(maxWidth:.infinity)
                        }.buttonStyle(.bordered).controlSize(.large)
                    }
                    footer
                }.padding(22).frame(maxWidth:640)
            }
            .background(Color(red:0.055, green:0.07, blue:0.06))
            .navigationTitle("SideRelay").navigationBarTitleDisplayMode(.inline)
            .tint(relayAccent)
            .fileImporter(isPresented:$picking, allowedContentTypes:[UTType(filenameExtension:"ipa") ?? .data]) { result in
                switch result { case .success(let url): model.importIPA(url); case .failure: model.reportPickerError() }
            }
            .sheet(item:$model.challenge) { challenge in
                ChallengeView(model:model, challenge:challenge).interactiveDismissDisabled()
            }
        }
    }
    private var header: some View {
        VStack(alignment:.leading, spacing:14) {
            HStack(spacing:12) {
                Image(systemName:"iphone.gen3.radiowaves.left.and.right").font(.system(size:36, weight:.light)).foregroundStyle(relayAccent)
                Text("iPhone → iPhone").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text("EXPERIMENTAL").font(.system(size:9,weight:.bold,design:.monospaced)).padding(7).background(.white.opacity(0.07),in:Capsule())
            }
            Text("Передай больше.\nБез компьютера.").font(.system(size:36,weight:.semibold,design:.rounded)).tracking(-1.3).fixedSize(horizontal:false,vertical:true)
            Text("Подпиши свой IPA на этом iPhone и установи его на второй по Wi-Fi.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var status: some View {
        VStack(alignment:.leading, spacing:14) {
            Label(model.installed ? "Установка подтверждена iOS" : model.busy ? "Сессия открыта" : "Готовимся к передаче", systemImage:model.installed ? "checkmark.circle.fill" : "circle.dotted.circle")
                .font(.headline).foregroundStyle(model.installed ? relayAccent : .primary)
            Text(model.message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            if model.busy { ProgressView(value:model.progress).tint(relayAccent) }
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:22))
    }
    private var setup: some View {
        VStack(alignment:.leading,spacing:20) {
            GroupBox {
                VStack(alignment:.leading,spacing:12) {
                    caption("01", "Приложение")
                    Button { picking = true } label: {
                        HStack {
                            Image(systemName:"shippingbox").font(.title2)
                            VStack(alignment:.leading,spacing:4) {
                                Text(model.fileName.isEmpty ? "Выбрать IPA" : model.fileName).lineLimit(2)
                                Text(model.fileName.isEmpty ? "Из «Файлов» · до 128 МБ" : model.sizeLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName:"plus")
                        }.frame(minHeight:54)
                    }.disabled(model.importing)
                    if model.importing { ProgressView() }
                }.padding(6)
            }
            GroupBox {
                VStack(alignment:.leading,spacing:14) {
                    caption("02", "Второй iPhone")
                    TextField("IP, например 192.168.1.42",text:$model.targetIP).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    Text("Оба телефона — в одной Wi-Fi сети. На втором: Настройки → Wi-Fi → ⓘ → IP-адрес. Для сопряжения без компьютера требуется iOS 27 и включённый Режим разработчика.").font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            GroupBox {
                VStack(alignment:.leading,spacing:14) {
                    caption("03", "Личная подпись")
                    TextField("Apple ID для подписи",text:$model.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    SecureField("Пароль Apple ID",text:$model.password).textFieldStyle(.roundedBorder)
                    Text("Используй аккаунт владельца второго телефона. Он вводится на этом iPhone; владелец должен доверять этому устройству. Пароль приложения не подходит. Пароль и токены не сохраняются между сессиями.").font(.caption).foregroundStyle(.secondary)
                    Toggle(isOn:$model.consent) {
                        Text("Разрешаю зарегистрировать второй iPhone, создать сертификат и App ID для выбранного IPA.").font(.caption)
                    }
                    DisclosureGroup("Дополнительно",isExpanded:$advanced) {
                        VStack(alignment:.leading,spacing:8) {
                            Text("Anisette v3 (HTTPS)").font(.caption)
                            TextField("https://…",text:$model.anisette).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            Text("Внешний сервис выдаёт данные для входа Apple. Приложение не отправляет ему пароль Apple ID.").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.top,8)
                    }.font(.caption)
                }.padding(6)
            }
            Button { model.start() } label: {
                Label("Сопрячь и установить",systemImage:"arrow.up.right").font(.headline).frame(maxWidth:.infinity).padding(.vertical,8)
            }.buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(.black).disabled(!model.canStart)
        }
    }
    @ViewBuilder private var pairing: some View {
        if !model.pin.isEmpty {
            VStack(alignment:.leading,spacing:14) {
                Text("Код для второго iPhone").font(.headline)
                Text(model.pin).font(.system(size:44,weight:.semibold,design:.monospaced)).tracking(5).foregroundStyle(relayAccent).minimumScaleFactor(0.5).lineLimit(1)
                Text("Введи этот код на втором телефоне. Оставь SideRelay открытым на первом.").font(.subheadline).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(relayAccent.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
        }
    }
    private var footer: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Держи оба телефона разблокированными. Сворачивание SideRelay завершает сессию. Кабель и LocalDevVPN для этого Wi-Fi режима не нужны.")
            Text("Бесплатная подпись обычно действует 7 дней. Сертификат и App ID остаются в Apple Account. Замена сертификата может отключить уже установленные приложения — SideRelay спросит отдельно. При установке SideStore / AltStore движок может встроить ключ подписи в приложение.")
            Link("Исходники и инструкция ↗",destination:URL(string:"https://github.com/CORBENDALLAS111/SideRelay")!)
            NavigationLink("Лицензии библиотек") { LicenseView() }
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func caption(_ number:String,_ title:String) -> some View {
        HStack { Text(number).font(.caption.monospaced()).foregroundStyle(relayAccent); Text(title).font(.headline) }
    }
}

private struct LicenseView: View {
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

private struct ChallengeView: View {
    let model: RelayModel
    let challenge: RelayChallenge
    @State private var code = ""
    @State private var pendingCertificate: RelayChoice?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    if challenge.kind == "device" {
                        Text("Это нужный iPhone?").font(.title.bold())
                        Text(challenge.data["name"] as? String ?? "iPhone").font(.title2)
                        Text("iOS \(challenge.data["version"] as? String ?? "—")")
                        Text("UDID: \(challenge.data["udid"] as? String ?? "—")").font(.caption.monospaced()).textSelection(.enabled)
                        Text("Установить: \(challenge.data["app"] as? String ?? "IPA")").font(.headline)
                        primary("Подписать и установить") { model.answer("confirm") }
                    } else if challenge.kind == "two_factor" {
                        Text("Подтверди вход в Apple").font(.title.bold())
                        Text("Введи код с доверенного устройства или из SMS.").foregroundStyle(.secondary)
                        TextField("Код подтверждения",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode).font(.title.monospaced()).textFieldStyle(.roundedBorder)
                        primary("Отправить код") { model.answer("code", value:code); code = "" }.disabled(code.count < 4)
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
                    Button("Отменить установку",role:.cancel) { model.answer("abort") }.frame(maxWidth:.infinity)
                }.padding(24)
            }.navigationTitle("SideRelay").navigationBarTitleDisplayMode(.inline)
            .tint(relayAccent)
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
        Button(action:action) { Text(title).frame(maxWidth:.infinity).padding(.vertical,6) }.buttonStyle(.borderedProminent).foregroundStyle(.black).controlSize(.large)
    }
}
