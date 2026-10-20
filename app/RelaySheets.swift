import SwiftUI

struct AccountSheet: View {
    @Bindable var model:RelayModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apple ID",text:$model.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Пароль",text:$model.password)
                } footer: { Text("Только на время этой сессии.") }
                Section { Toggle("Разрешить подпись",isOn:$model.consent) } footer: { Text("Регистрация второго iPhone, сертификата и App ID в этом аккаунте.") }
                Section {
                    DisclosureGroup("О подписи") {
                        Text("Сертификат и App ID остаются в Apple Account. При подписи SideStore или другого поддерживаемого sideloader ключ сертификата может попасть в установленное приложение.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GlassAction(title:"Готово",symbol:"checkmark",enabled:model.hasAccount) { dismiss() }.listRowBackground(Color.clear)
            }.navigationTitle("Apple Account").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Закрыть") { dismiss() } } }.tint(relayTint)
        }.presentationDetents([.medium,.large])
    }
}
struct SettingsSheet: View {
    @Bindable var model:RelayModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Соединение") {
                    TextField("Anisette v3 · HTTPS",text:$model.anisette).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                    Link("Локальная сеть",destination:URL(string:UIApplication.openSettingsURLString)!)
                }
                Section("Диагностика") {
                    if model.diagnostics.isEmpty { Text("Появится после подключения").foregroundStyle(.secondary) }
                    else {
                        Text(model.diagnostics.joined(separator:"\n")).font(.system(.caption2,design:.monospaced)).textSelection(.enabled)
                        Button(copied ? "Скопировано" : "Скопировать") { model.copyDiagnostics(); copied = true }
                    }
                }
                Section {
                    NavigationLink("Лицензии") { LicenseView() }
                    Link("GitHub",destination:URL(string:"https://github.com/CORBENDALLAS111/SideRelay")!)
                } footer: { Text("SideRelay 0.2.0 · экспериментальная версия") }
            }.navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Готово") { dismiss() } } }.tint(relayTint)
        }
    }
}
struct ConnectionHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Label("SideRelay открыт на первом iPhone",systemImage:"1.circle")
                Label("На втором: Developer Mode → SideRelay",systemImage:"2.circle")
                Label("Введи показанный код на втором",systemImage:"3.circle")
                Text("Нужны iOS 27, общая Wi-Fi сеть и разрешение «Локальная сеть».").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Подключение").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Понятно") { dismiss() } } }.tint(relayTint)
        }.presentationDetents([.medium])
    }
}
