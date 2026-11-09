import SwiftUI
import Network

struct ConnectionHelp: View {
    let useAddress: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @AppStorage("setupConnection") private var connection = "wifi"

    private let titles = ["Соедини устройства", "Подготовь устройство", "Добавь приложение", "Подтверди установку"]
    private let icons = ["network", "gearshape", "shippingbox", "checkmark.shield"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    progress
                    VStack(alignment:.leading,spacing:18) {
                        Image(systemName:icons[step]).font(.system(.title,design:.rounded,weight:.medium))
                            .frame(width:56,height:56).background(.white.opacity(0.10),in:RoundedRectangle(cornerRadius:18))
                            .accessibilityHidden(true)
                        Text(L(titles[step])).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        instructions
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .id(step).transition(.opacity)
                }
                .frame(maxWidth:520).padding(24).frame(maxWidth:.infinity)
            }
            .id(step).transition(.opacity)
            .background { RelayBackdrop() }
            .safeAreaInset(edge:.bottom) { controls }
            .navigationTitle(L("Настройка SideRelay")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button(L("Закрыть")) { dismiss() } } }
            .tint(relayTint)
            #if DEBUG
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("ethernet") { connection = "ethernet" }
                if args.contains("hotspot") { connection = "hotspot" }
            }
            #endif
        }.presentationDetents([.large])
    }

    private var progress: some View {
        HStack(spacing:6) {
            ForEach(titles.indices,id:\.self) { index in
                Capsule().fill(.white.opacity(index <= step ? 0.88 : 0.16)).frame(height:3)
            }
        }.accessibilityElement(children:.ignore)
            .accessibilityLabel(L("Шаг %@ из %@",String(step + 1),String(titles.count)))
    }

    private var controls: some View {
        HStack(spacing:12) {
            if step > 0 {
                Button(L("Назад")) { move(-1) }.buttonStyle(.bordered).controlSize(.large)
            }
            GlassAction(title:step == titles.count - 1 ? L("Готово") : L("Далее"),
                        symbol:step == titles.count - 1 ? "checkmark" : "arrow.right") {
                if step == titles.count - 1 { dismiss() } else { move(1) }
            }
        }.frame(maxWidth:520).padding(.horizontal,24).padding(.vertical,10)
            .frame(maxWidth:.infinity).background(.ultraThinMaterial)
    }

    private func move(_ direction: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration:0.32)) { step += direction }
    }

    @ViewBuilder private var instructions: some View {
        switch step {
        case 0:
            Text(L("На первом устройстве открыт SideRelay. На целевом устанавливается приложение."))
                .foregroundStyle(.secondary)
            Picker(L("Соединение"),selection:$connection) {
                Text("Wi-Fi").tag("wifi")
                Text(L("Модем")).tag("hotspot")
                Text("Ethernet").tag("ethernet")
            }.pickerStyle(.segmented)
            VStack(alignment:.leading,spacing:12) {
                if connection == "ethernet" {
                    Text(L("Подключи оба устройства Ethernet-адаптерами к одной сети. Wi-Fi можно выключить. Для входа в Apple первому устройству нужен интернет."))
                    EthernetStatus()
                    DisclosureGroup(L("Два адаптера и кабель без роутера")) {
                        Text(L("Соедини адаптеры Ethernet-кабелем. В настройках Ethernet задай вручную 192.168.50.1 на первом устройстве и 192.168.50.2 на целевом, маска 255.255.255.0. Поле роутера оставь пустым. Для Apple Account нужен отдельный доступ в интернет."))
                            .font(.subheadline).padding(.top,6)
                        Button(L("Использовать адрес 192.168.50.2")) {
                            useAddress("192.168.50.2")
                            move(1)
                        }
                            .font(.subheadline.weight(.semibold)).padding(.top,6)
                    }
                    Text(L("Ethernet не проверен на физических устройствах. Прямой USB-C между устройствами не поддерживается."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else if connection == "hotspot" {
                    row("1", "Включи режим модема", "На первом устройстве включи сотовые данные. Открой «Настройки → Режим модема» и включи «Разрешать другим». Не закрывай этот экран до подключения второго устройства.")
                    row("2", "Подключи целевое устройство", "На целевом открой «Настройки → Wi-Fi» и выбери сеть первого устройства. Нажми ⓘ рядом с сетью и запиши IPv4 целевого устройства. Вернись в SideRelay на первом устройстве.")
                    Text(L("Роутер не нужен. IPA передаётся по локальной сети модема. Сотовые данные нужны для входа и подписи Apple. Если SideRelay не появляется в режиме разработчика, этот модем может не пропускать обнаружение устройств."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(L("Подключи оба устройства к одной Wi-Fi сети. Если устройства не видят друг друга, попробуй обычную сеть вместо гостевой или точки доступа."))
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
                .background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:20))
                .animation(reduceMotion ? nil : .smooth(duration:0.28),value:connection)
            Text(L("Разреши SideRelay доступ к локальной сети, когда система попросит.")).font(.subheadline).foregroundStyle(.secondary)
        case 1:
            row("1", "Включи режим разработчика", "На целевом устройстве нужна iOS / iPadOS 27 с доступным сопряжением. Открой «Настройки → Конфиденциальность и безопасность → Режим разработчика». Если потребуется, перезагрузи устройство и подтверди включение.")
            row("2", "Найди адрес", "На целевом открой сведения о текущей сети в «Wi-Fi» или «Ethernet». Запиши IPv4, например 192.168.1.42. Адреса 169.254.x.x не подходят.")
        case 2:
            row("1", "Выбрать IPA", "На первом устройстве выбери доступный файл .ipa до 128 МБ. Если он в iCloud, дождись загрузки. Введи IPv4 целевого устройства.")
            row("2", "Введи Apple Account", "Открой Apple Account, введи обычный пароль и разреши подпись. Пароль приложения не подходит. SideRelay запросит пароль снова при повторе.")
            row("3", "Нажми «Установить»", "Оставь SideRelay открытым и первое устройство разблокированным.")
        default:
            row("1", "Введи код сопряжения", "На целевом устройстве в настройках режима разработчика выбери SideRelay. Когда на первом устройстве появятся шесть цифр, введи их на целевом.")
            row("2", "Проверь и подтверди", "Проверь устройство и приложение на первом устройстве. Если Apple запросит 2FA, введи этот код в SideRelay. Код Apple и код сопряжения — разные.")
            row("3", "Дождись установки", "После подтверждения iOS открой приложение на целевом устройстве. Если система попросит, доверься разработчику в «Настройки → Основные → VPN и управление устройством».")
            DisclosureGroup(L("Не появляется код")) {
                Text(L("Проверь IPv4, разрешение «Локальная сеть» и доступ между устройствами. Нажми «Установить» на первом устройстве, затем снова выбери SideRelay на целевом."))
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top,6)
            }
            DisclosureGroup(L("Ошибка подписи или установки")) {
                Text(L("Открой «Настройки → Диагностика» в SideRelay. Проверь вход на account.apple.com и доступ к Apple Developer. Если Apple ограничил сертификаты, не отзывай используемый сертификат без необходимости: подписанные им приложения могут перестать открываться. При ошибке передачи проверь целевое устройство перед повтором."))
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top,6)
            }
        }
    }

    private func row(_ number:String,_ title:String,_ detail:String) -> some View {
        HStack(alignment:.top,spacing:12) {
            Text(number).font(.caption.monospacedDigit().weight(.semibold))
                .frame(width:26,height:26).background(.white.opacity(0.10),in:Circle()).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:5) {
                Text(L(title)).font(.headline)
                Text(L(detail)).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(14).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:18))
    }
}

private struct EthernetStatus: View {
    @State private var connected: Bool?

    var body: some View {
        Label(connected.map { $0 ? L("Ethernet обнаружен на этом устройстве") : L("Ethernet пока не обнаружен") } ?? L("Проверяем Ethernet…"),
              systemImage:connected == true ? "checkmark.circle" : "cable.connector")
            .font(.footnote.weight(.medium))
            .task {
                let monitor = NWPathMonitor(requiredInterfaceType:.wiredEthernet)
                let updates = AsyncStream<Bool>(bufferingPolicy:.bufferingNewest(1)) { stream in
                    monitor.pathUpdateHandler = { path in
                        stream.yield(path.status == .satisfied && path.usesInterfaceType(.wiredEthernet))
                    }
                    stream.onTermination = { _ in monitor.cancel() }
                    monitor.start(queue:DispatchQueue(label:"SideRelay.Ethernet"))
                }
                for await available in updates { connected = available }
            }
    }
}
