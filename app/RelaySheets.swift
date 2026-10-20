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
                } footer: { Text("Пароль используется только в текущей сессии. После каждой попытки его нужно ввести заново.") }
                Section { Toggle("Разрешить подпись",isOn:$model.consent) } footer: { Text("Регистрация целевого устройства, сертификата и App ID в этом аккаунте.") }
                Section {
                    DisclosureGroup("О подписи") {
                        Text("Сертификат и App ID остаются в Apple Account. При подписи SideStore или другого поддерживаемого sideloader ключ сертификата может попасть в установленное приложение.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GlassAction(title:"Готово",symbol:"checkmark",enabled:model.hasAccount) { dismiss() }.listRowBackground(Color.clear)
            }.navigationTitle("Apple Account").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Закрыть") { dismiss() } } }.tint(relayTint)
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
                Section("Соединение") {
                    Picker("Anisette", selection:$model.anisette) {
                        Text("jkcoxson · Windows ADI").tag("https://ani.jkcoxson.com")
                        Text("SideStore · Windows ADI").tag("https://win.ani.sidestore.io")
                        Text("StikStore · Windows ADI").tag("https://ani2.stikstore.app")
                        if !["https://ani.jkcoxson.com","https://win.ani.sidestore.io","https://ani2.stikstore.app"].contains(model.anisette) {
                            Text("Свой сервер").tag(model.anisette)
                        }
                    }.disabled(model.busy)
                    DisclosureGroup("Свой сервер") {
                        TextField("Anisette v3 · HTTPS",text:$model.anisette).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                    }
                    Link("Локальная сеть",destination:URL(string:UIApplication.openSettingsURLString)!)
                }
                Section("Диагностика") {
                    if model.diagnostics.isEmpty { Text("Появится после подключения").foregroundStyle(.secondary) }
                    else {
                        Text(model.diagnostics.joined(separator:"\n")).font(.system(.caption2,design:.monospaced)).textSelection(.enabled)
                        Button(copied ? "Скопировано" : "Скопировать") { model.copyDiagnostics(); copied = true }
                    }
                }
                Section("Авторы") {
                    Text("Zephyrax")
                    Text("CORBENDALLAS111")
                }
                Section {
                    NavigationLink("Лицензии") { LicenseView() }
                    Link("GitHub",destination:URL(string:"https://github.com/CORBENDALLAS111/SideRelay")!)
                } footer: { Text("SideRelay \(RelayBuild.version) · экспериментальная версия") }
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
                Section {
                    Text("Первое устройство запускает SideRelay и подписывает IPA. Целевое устройство получает приложение; SideRelay на нём не требуется.")
                }
                Section("1 · Подготовь целевое устройство") {
                    step("Проверь систему", "Для подключения без компьютера нужна iOS / iPadOS 27 с доступным сопряжением в режиме разработчика. Одного IP-адреса недостаточно.")
                    step("Включи режим разработчика", "Настройки → Конфиденциальность и безопасность → Режим разработчика. Включи его, перезагрузи устройство, разблокируй и подтверди включение, если система попросит.")
                    step("Посмотри IP", "Настройки → Wi-Fi → ⓘ у текущей сети → IP-адрес. Нужен IPv4, например 192.168.1.42. Впиши его в SideRelay на первом устройстве.")
                }
                Section("2 · Настрой первое устройство") {
                    step("Подключи оба устройства к одной Wi-Fi сети", "Разреши SideRelay доступ к локальной сети. Гостевая сеть с изоляцией клиентов не подходит. Для входа Apple и anisette нужен интернет.")
                    step("Выбери IPA", "Нажми «Выбрать IPA». Если файл лежит в iCloud, сначала дождись его загрузки. Поддерживается файл размером до 128 МБ.")
                    step("Введи Apple Account", "Открой строку Apple Account, введи обычный пароль аккаунта, разреши подпись и нажми «Готово». Пароль приложения не подходит. Данные вводятся на первом устройстве — оно должно быть доверенным.")
                    step("Нажми «Установить»", "Оставь SideRelay открытым и первое устройство разблокированным. Теперь оно станет доступно для сопряжения.")
                }
                Section("3 · Соедини устройства") {
                    step("На целевом открой режим разработчика", "Настройки → Конфиденциальность и безопасность → Режим разработчика → доступное сопряжение с SideRelay. Выбирай SideRelay именно на целевом устройстве.")
                    step("Дождись кода на первом", "Код появится в SideRelay только после выбора на целевом устройстве. Введи эти шесть цифр в системном окне целевого устройства.")
                    step("Проверь устройство", "На первом появятся имя, версия системы, UDID и название приложения. Убедись, что это нужное устройство, и подтверди подпись.")
                }
                Section("4 · Подпись и установка") {
                    step("Подтверди вход Apple", "Если Apple запросит 2FA, введи свежий код в SideRelay на первом устройстве. Код может прийти на доверенное устройство или по SMS. Код Apple и код сопряжения — разные коды.")
                    step("Дождись подтверждения iOS", "Не закрывай SideRelay и держи целевое устройство доступным в сети. После сообщения об установке найди приложение на целевом устройстве.")
                    step("Доверься разработчику, если требуется", "На целевом: Настройки → Основные → VPN и управление устройством → профиль разработчика. Подтверди доверие и попробуй открыть приложение.")
                }
                Section("Другие способы подключения") {
                    DisclosureGroup("Ethernet вместо Wi-Fi") {
                        Text("Подключи каждое устройство через совместимый USB-C Ethernet-адаптер к общей локальной сети с роутером и DHCP. В настройках Ethernet целевого устройства найди IPv4 и введи его в SideRelay. Нужны локальные адреса 10.x, 172.16–31.x или 192.168.x, доступ между устройствами и Bonjour. Для входа Apple нужен интернет. Прямое соединение двух адаптеров без настройки адресов не гарантирует работу: адреса 169.254.x.x эта версия не принимает. Сценарий на физических устройствах пока не проверен.")
                    }
                    DisclosureGroup("Персональная точка доступа") {
                        Text("Можно попробовать включить «Режим модема» на одном устройстве и подключить второе к этой сети. Проверь IP целевого устройства и доступ к интернету. Работа сопряжения зависит от прохождения Bonjour и соединений между устройствами: если SideRelay не появляется, используй обычную общую сеть. Этот сценарий пока не подтверждён тестами на устройствах.")
                    }
                    Text("Прямая установка через USB-C кабель между двумя устройствами в SideRelay не поддерживается.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Если не получилось") {
                    DisclosureGroup("Нет SideRelay или не появляется код") {
                        Text("Проверь IP, общую сеть и доступ «Локальная сеть» в настройках SideRelay. Убедись, что «Установить» уже нажато на первом устройстве. Выбери SideRelay в режиме разработчика целевого устройства ещё раз. Если пункта сопряжения нет, этот способ подключения для системы недоступен.")
                    }
                    DisclosureGroup("Ошибка входа Apple") {
                        Text("В настройках SideRelay открой диагностику: AUTH_ANISETTE — подготовка anisette, AUTH_APPLE_LOGIN — вход Apple, AUTH_DEVELOPER — доступ к разработке. Проверь вход на account.apple.com, подтверждение email и условия developer.apple.com. При HTTP 429 подожди; при сбое anisette попробуй другой Windows ADI сервер. Вход после 2FA может занять время.")
                    }
                    DisclosureGroup("Лимит сертификатов или приложений") {
                        Text("Бесплатный аккаунт обычно ограничен тремя активными приложениями на устройстве и недельным лимитом App ID. Отзыв сертификата может отключить уже подписанные им SideStore и LiveContainer. Если не уверен, отмени замену и используй другой аккаунт.")
                    }
                    DisclosureGroup("После ошибки всё нужно выбрать снова") {
                        Text("Нажми «Повторить»: SideRelay попробует заново импортировать исходный IPA и откроет ввод пароля. Если доступ к исходному файлу потерян, выбери его вручную. Старые временные файлы и пароль не сохраняются. После начала передачи сначала проверь целевое устройство: приложение могло успеть установиться.")
                    }
                    DisclosureGroup("Что отправить авторам") {
                        Text("Настройки SideRelay → Диагностика → Скопировать. В диагностике только этапы и коды ошибок. Не отправляй пароль, коды подтверждения, сертификаты и pairing-ключи.")
                    }
                }
                Section {
                    Text("У бесплатной подписи обычно срок 7 дней. Сертификат, App ID и регистрация устройства остаются в Apple Account. Файл IPA и данные сессии очищаются после завершения.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Подключение").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Понятно") { dismiss() } } }.tint(relayTint)
        }.presentationDetents([.large])
    }
    private func step(_ title:String,_ detail:String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(.vertical,4)
    }
}
