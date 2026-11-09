import SwiftUI

struct AccountSheet: View {
    @Bindable var model:RelayModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apple ID",text:$model.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(L("Пароль"),text:$model.password)
                } footer: { Text(L("Пароль используется только в текущей сессии. После каждой попытки его нужно ввести заново.")) }
                Section { Toggle(L("Разрешить подпись"),isOn:$model.consent) } footer: { Text(L("Регистрация целевого устройства, сертификата и App ID в этом аккаунте.")) }
                Section {
                    DisclosureGroup(L("О подписи")) {
                        Text(L("Сертификат и App ID остаются в Apple Account. При подписи SideStore или другого поддерживаемого sideloader ключ сертификата может попасть в установленное приложение.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GlassAction(title:L("Готово"),symbol:"checkmark",enabled:model.hasAccount) { dismiss() }.listRowBackground(Color.clear)
            }.navigationTitle("Apple Account").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button(L("Закрыть")) { dismiss() } } }.tint(relayTint)
        }.presentationDetents([.large])
    }
}
struct SettingsSheet: View {
    @Bindable var model:RelayModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Соединение")) {
                    Picker("Anisette", selection:$model.anisette) {
                        Text("jkcoxson · Windows ADI").tag("https://ani.jkcoxson.com")
                        Text("SideStore · Windows ADI").tag("https://win.ani.sidestore.io")
                        Text("StikStore · Windows ADI").tag("https://ani2.stikstore.app")
                        if !["https://ani.jkcoxson.com","https://win.ani.sidestore.io","https://ani2.stikstore.app"].contains(model.anisette) {
                            Text(L("Свой сервер")).tag(model.anisette)
                        }
                    }.disabled(model.busy)
                    DisclosureGroup(L("Свой сервер")) {
                        TextField("Anisette v3 · HTTPS",text:$model.anisette).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                    }
                    Link(L("Локальная сеть"),destination:URL(string:UIApplication.openSettingsURLString)!)
                }
                Section(L("Диагностика")) {
                    if model.diagnostics.isEmpty { Text(L("Появится после подключения")).foregroundStyle(.secondary) }
                    else {
                        Text(model.diagnostics.joined(separator:"\n")).font(.system(.caption2,design:.monospaced)).textSelection(.enabled)
                        Button(copied ? L("Скопировано") : L("Скопировать")) { model.copyDiagnostics(); copied = true }
                    }
                }
                Section(L("Авторы")) {
                    Text("Zephyrax")
                    Text("CORBENDALLAS111")
                }
                Section {
                    NavigationLink(L("Лицензии")) { LicenseView() }
                    Link("GitHub",destination:URL(string:"https://github.com/CORBENDALLAS111/SideRelay")!)
                } footer: { Text(L("SideRelay %@ · экспериментальная версия",RelayBuild.version)) }
            }.navigationTitle(L("Настройки")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button(L("Готово")) { dismiss() } } }.tint(relayTint)
        }
    }
}
