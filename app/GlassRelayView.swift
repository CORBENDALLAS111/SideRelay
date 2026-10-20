import SwiftUI
import UniformTypeIdentifiers

struct RelayView: View {
    @Bindable var model:RelayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var picking = false
    @State private var account = false
    @State private var settings = false
    @State private var help = false
    @State private var retryPending = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @ScaledMetric(relativeTo:.largeTitle) private var pinFontSize: CGFloat = 46
    @Namespace private var glass
    var body: some View {
        NavigationStack {
            ZStack {
                RelayBackdrop()
                ScrollView {
                    VStack(spacing:24) {
                        if model.installed { InstallationSuccess().accessibilityHidden(true) }
                        VStack(spacing:7) {
                            Text(model.statusTitle).font(.title.weight(.semibold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                            if model.busy && model.pin.isEmpty {
                                Text(model.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }
                        LiquidGroup {
                            GlassPanel(id:"session",namespace:glass) { if model.busy { liveSession } else { setup } }
                        }
                        if model.stage == .error {
                            Text(model.message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Диагностика") { settings = true }.font(.footnote)
                        }
                        if model.busy {
                            GlassAction(title:"Отменить",symbol:"xmark",prominent:false,hint:"Остановить текущую сессию установки") { model.cancel() }
                        } else if model.stage == .error {
                            GlassAction(title:"Повторить",symbol:"arrow.clockwise",enabled:!model.importing,hint:"Снова выбрать IPA и ввести пароль для новой попытки") {
                                retryPending = true
                                if !model.prepareRetry() { picking = true }
                            }
                        } else {
                            GlassAction(title:"Установить",symbol:"arrow.up.right",enabled:model.canStart,hint:"Начать сопряжение, подпись и установку на целевое устройство") { model.start() }
                        }
                        if !model.busy { Text("Оба устройства в одной локальной сети").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.horizontal,24).padding(.top,8).padding(.bottom,30).frame(maxWidth:540).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("SideRelay").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button { help = true } label: { Image(systemName:"questionmark") }.accessibilityLabel("Подключение") }
                ToolbarItem(placement:.topBarTrailing) { Button { settings = true } label: { Image(systemName:"slider.horizontal.3") }.accessibilityLabel("Настройки") }
            }.tint(relayTint)
            .animation(reduceMotion ? nil : .spring(response:0.5,dampingFraction:0.83),value:model.busy)
            .animation(reduceMotion ? nil : .spring(response:0.45,dampingFraction:0.82),value:model.pin)
            .sensoryFeedback(.selection,trigger:model.pin)
            .sensoryFeedback(trigger:model.installed) { _,new in new ? .success : nil }
            .sensoryFeedback(trigger:model.stage) { _,new in new == .error ? .error : nil }
            .onChange(of:model.importing) { _,loading in
                if !loading && retryPending && model.stage != .error && !model.fileName.isEmpty {
                    retryPending = false
                    account = true
                }
            }
            .fileImporter(isPresented:$picking,allowedContentTypes:[UTType(filenameExtension:"ipa") ?? .data]) { result in
                switch result { case .success(let url): model.importIPA(url); case .failure: retryPending = false; model.reportPickerError() }
            }
            .onAppear {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of:"--ui-preview"), args.count > index + 1 {
                    switch args[index + 1] {
                    case "account": account = true
                    case "guide": help = true
                    case "settings": settings = true
                    default: break
                    }
                    return
                }
                #endif
                if !hasSeenOnboarding { help = true }
            }
            .sheet(isPresented:$account) { AccountSheet(model:model) }
            .sheet(isPresented:$settings) { SettingsSheet(model:model) }
            .sheet(isPresented:$help,onDismiss:{ hasSeenOnboarding = true }) { ConnectionHelp() }
            .sheet(item:$model.challenge) { challenge in ChallengeView(model:model,challenge:challenge).interactiveDismissDisabled() }
        }
    }
    private var setup: some View {
        VStack(spacing:0) {
            Button { picking = true } label: {
                HStack(spacing:14) {
                    rowIcon("shippingbox")
                    VStack(alignment:.leading,spacing:4) {
                        Text(model.fileName.isEmpty ? "Выбрать IPA" : model.fileName).lineLimit(1)
                        if !model.fileName.isEmpty { Text(model.sizeLabel).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength:4)
                    if model.importing { ProgressView() } else { Image(systemName:model.fileName.isEmpty ? "plus" : "checkmark").foregroundStyle(model.fileName.isEmpty ? relayTint : .white) }
                }.frame(minHeight:56).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.importing)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Файл IPA")
                .accessibilityValue(model.fileName.isEmpty ? "Не выбран" : "\(model.fileName), \(model.sizeLabel)")
                .accessibilityHint("Открывает выбор файла приложения")
            divider
            HStack(spacing:14) {
                rowIcon("wifi")
                TextField("IP целевого устройства",text:$model.targetIP).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("IP целевого устройства")
            }.frame(minHeight:62)
            divider
            Button { account = true } label: {
                HStack(spacing:14) {
                    rowIcon("person.crop.circle")
                    Text(model.email.isEmpty ? "Apple Account" : model.email).lineLimit(1)
                    Spacer(minLength:4)
                    Image(systemName:model.hasAccount ? "checkmark" : "chevron.right").font(.subheadline).foregroundStyle(model.hasAccount ? Color.white : Color.secondary)
                }.frame(minHeight:62).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Apple Account")
                .accessibilityValue(model.hasAccount ? "Данные готовы к подписи" : "Нужны данные для подписи")
                .accessibilityHint("Открывает данные аккаунта и разрешение подписи")
        }
    }
    private var liveSession: some View {
        VStack(spacing:22) {
            if !model.pin.isEmpty {
                Group {
                    if dynamicType.isAccessibilitySize {
                        VStack(spacing:8) { Text(String(model.pin.prefix(3))); Text(String(model.pin.suffix(3))) }
                    } else { Text(model.pin) }
                }.font(.system(size:pinFontSize,weight:.medium,design:.monospaced)).tracking(4).minimumScaleFactor(0.4).lineLimit(1).contentTransition(.numericText())
                    .accessibilityElement(children:.ignore).accessibilityLabel("Код сопряжения").accessibilityValue(model.pin.map(String.init).joined(separator:" "))
                Text("Введи на целевом устройстве").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if model.stage == .pairing || model.stage == .handshake {
                Text("··· ···").font(.system(size:pinFontSize,weight:.medium,design:.monospaced)).tracking(6).foregroundStyle(.tertiary)
                Text(model.stage == .handshake ? "Готовим код…" : "Код появится после подключения").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value:model.progress).tint(relayTint).accessibilityLabel("Ход установки").accessibilityValue(Text(model.progress,format:.percent.precision(.fractionLength(0))))
                Text(model.progress,format:.percent.precision(.fractionLength(0))).font(.system(.title2,design:.rounded).monospacedDigit()).contentTransition(.numericText())
            }
        }.frame(maxWidth:.infinity).padding(.vertical,8)
    }
    private var divider: some View { Divider().overlay(.white.opacity(0.05)).padding(.leading,44) }
    private func rowIcon(_ name:String) -> some View { Image(systemName:name).font(.system(size:20)).foregroundStyle(relayTint).frame(width:28) }
}

struct LiquidGroup<Content:View>: View {
    @ViewBuilder let content:Content
    var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing:18) { content } } else { content }
    }
}
private struct GlassPanel<Content:View>: View {
    let id:String
    let namespace:Namespace.ID
    @ViewBuilder let content:Content
    var body: some View {
        if #available(iOS 26, *) {
            surface.glassEffect(.regular.tint(.white.opacity(0.12)),in:.rect(cornerRadius:28)).glassEffectID(id,in:namespace)
        } else {
            surface.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:28))
        }
    }
    private var surface: some View {
        content.padding(20)
            .background(LinearGradient(colors:[.white.opacity(0.14),.white.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:28))
            .overlay { RoundedRectangle(cornerRadius:28).strokeBorder(.white.opacity(0.16),lineWidth:0.75).allowsHitTesting(false) }
    }
}
struct GlassAction: View {
    let title:String
    let symbol:String
    var prominent = true
    var enabled = true
    var hint = ""
    @State private var activation = false
    let action:()->Void
    var body: some View {
        if #available(iOS 26, *) {
            if prominent { button.buttonStyle(.glassProminent) }
            else {
                button.buttonStyle(.plain).padding(.vertical,12)
                    .background(LinearGradient(colors:[.white.opacity(0.12),.white.opacity(0.05)],startPoint:.topLeading,endPoint:.bottomTrailing),in:Capsule())
                    .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(),in:.capsule)
            }
        } else { button.buttonStyle(.borderedProminent) }
    }
    private var button: some View {
        Button { activation.toggle(); action() } label: { HStack(spacing:8) { Image(systemName:symbol).foregroundStyle(.white); Text(title).foregroundStyle(prominent ? Color.white : relayTint) }.font(.headline).frame(maxWidth:.infinity).frame(minHeight:44) }.controlSize(.large).disabled(!enabled).accessibilityHint(hint).sensoryFeedback(.selection,trigger:activation)
    }
}

private struct RelayBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/24,paused:reduceMotion || phase != .active)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.16
            MeshGradient(width:3,height:3,points:[
                [0,0],[0.5,0],[1,0],[0,0.5],[Float(0.5 + sin(t)*0.14),Float(0.5 + cos(t)*0.15)],[1,0.5],[0,1],[0.5,1],[1,1]
            ],colors:[
                Color(red:0.035,green:0.10,blue:0.17),Color(red:0.10,green:0.25,blue:0.34),Color(red:0.12,green:0.13,blue:0.27),
                Color(red:0.07,green:0.24,blue:0.29),Color(red:0.12,green:0.34,blue:0.36),Color(red:0.17,green:0.17,blue:0.34),
                Color(red:0.03,green:0.06,blue:0.12),Color(red:0.04,green:0.09,blue:0.17),Color(red:0.07,green:0.05,blue:0.16)
            ])
        }.ignoresSafeArea()
    }
}

private struct InstallationSuccess: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo:.largeTitle) private var size: CGFloat = 68
    @State private var appeared = false
    var body: some View {
        Image(systemName:"checkmark.circle.fill")
            .symbolRenderingMode(.palette).foregroundStyle(.white,relayTint.opacity(0.35))
            .font(.system(size:size,weight:.light))
            .scaleEffect(appeared ? 1 : 0.65).opacity(appeared ? 1 : 0)
            .symbolEffect(.bounce,value:reduceMotion ? false : appeared)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response:0.5,dampingFraction:0.6)) { appeared = true } }
    }
}

#if DEBUG
struct RelayPreviewType: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of:"--ui-preview"), args.count > index + 1, args[index + 1] == "large" {
            content.dynamicTypeSize(.accessibility5)
        } else { content }
    }
}
#endif
