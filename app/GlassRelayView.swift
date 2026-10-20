import SwiftUI
import UniformTypeIdentifiers

let relayTint = Color(red:0.52,green:0.91,blue:0.86)

struct RelayView: View {
    @Bindable var model:RelayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picking = false
    @State private var account = false
    @State private var settings = false
    @State private var help = false
    @Namespace private var glass
    var body: some View {
        NavigationStack {
            ZStack {
                RelayBackdrop()
                ScrollView {
                    VStack(spacing:24) {
                        ConnectionArt(active:model.busy,complete:model.installed).frame(height:185).accessibilityHidden(true)
                        VStack(spacing:7) {
                            Text(model.statusTitle).font(.system(size:30,weight:.semibold,design:.rounded)).multilineTextAlignment(.center)
                            if model.busy && model.pin.isEmpty {
                                Text(model.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }
                        LiquidGroup {
                            GlassPanel(id:"session",namespace:glass) { if model.busy { liveSession } else { setup } }
                        }
                        if model.stage == "error" {
                            Text(model.message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Диагностика") { settings = true }.font(.footnote)
                        }
                        if model.busy { GlassAction(title:"Отменить",symbol:"xmark",prominent:false) { model.cancel() } }
                        else { GlassAction(title:"Установить",symbol:"arrow.up.right",enabled:model.canStart) { model.start() } }
                        if !model.busy { Text("Оба iPhone в одной Wi-Fi сети").font(.caption).foregroundStyle(.secondary) }
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
            .fileImporter(isPresented:$picking,allowedContentTypes:[UTType(filenameExtension:"ipa") ?? .data]) { result in
                switch result { case .success(let url): model.importIPA(url); case .failure: model.reportPickerError() }
            }
            .sheet(isPresented:$account) { AccountSheet(model:model) }
            .sheet(isPresented:$settings) { SettingsSheet(model:model) }
            .sheet(isPresented:$help) { ConnectionHelp() }
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
                    if model.importing { ProgressView() } else { Image(systemName:model.fileName.isEmpty ? "plus" : "checkmark").foregroundStyle(relayTint) }
                }.frame(minHeight:56).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.importing)
            divider
            HStack(spacing:14) {
                rowIcon("wifi")
                TextField("IP второго iPhone",text:$model.targetIP).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("IP второго iPhone")
            }.frame(minHeight:62)
            divider
            Button { account = true } label: {
                HStack(spacing:14) {
                    rowIcon("person.crop.circle")
                    Text(model.email.isEmpty ? "Apple Account" : model.email).lineLimit(1)
                    Spacer(minLength:4)
                    Image(systemName:model.hasAccount ? "checkmark" : "chevron.right").font(.subheadline).foregroundStyle(model.hasAccount ? relayTint : Color.secondary)
                }.frame(minHeight:62).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
    private var liveSession: some View {
        VStack(spacing:22) {
            if !model.pin.isEmpty {
                Text(model.pin).font(.system(size:46,weight:.medium,design:.monospaced)).tracking(6).minimumScaleFactor(0.55).lineLimit(1).contentTransition(.numericText()).accessibilityLabel("Код сопряжения: \(model.pin)")
                Text("Введи на втором iPhone").font(.subheadline).foregroundStyle(.secondary)
            } else if model.stage == "pairing" || model.stage == "handshake" {
                Text("··· ···").font(.system(size:46,weight:.medium,design:.monospaced)).tracking(6).foregroundStyle(.tertiary)
                Text(model.stage == "handshake" ? "Готовим код…" : "Код появится после подключения").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value:model.progress).tint(relayTint)
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
        if #available(iOS 26, *) { content.padding(20).glassEffect(.regular,in:.rect(cornerRadius:28)).glassEffectID(id,in:namespace) }
        else { content.padding(20).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:28)) }
    }
}
struct GlassAction: View {
    let title:String
    let symbol:String
    var prominent = true
    var enabled = true
    let action:()->Void
    var body: some View {
        if #available(iOS 26, *) {
            if prominent { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.glass) }
        } else { button.buttonStyle(.borderedProminent) }
    }
    private var button: some View {
        Button(action:action) { Label(title,systemImage:symbol).font(.headline).frame(maxWidth:.infinity).frame(minHeight:44) }.controlSize(.large).disabled(!enabled)
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
                Color(red:0.025,green:0.06,blue:0.13),Color(red:0.07,green:0.14,blue:0.25),Color(red:0.03,green:0.09,blue:0.16),
                Color(red:0.05,green:0.17,blue:0.23),Color(red:0.09,green:0.27,blue:0.30),Color(red:0.10,green:0.11,blue:0.27),
                Color(red:0.03,green:0.06,blue:0.12),Color(red:0.04,green:0.09,blue:0.17),Color(red:0.07,green:0.05,blue:0.16)
            ])
        }.ignoresSafeArea().overlay(.black.opacity(0.12)).ignoresSafeArea()
    }
}
private struct ConnectionArt: View {
    let active:Bool
    let complete:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass
    var body: some View {
        LiquidGroup {
            HStack(spacing:26) {
                phone(index:0)
                Image(systemName:complete ? "checkmark" : "arrow.right").font(.system(size:22,weight:.medium)).foregroundStyle(relayTint).contentTransition(.symbolEffect(.replace)).symbolEffect(.pulse,options:.repeating,isActive:active && !reduceMotion)
                phone(index:1)
            }.phaseAnimator(reduceMotion ? [false] : [false,true]) { content,phase in content.offset(y:phase ? -5 : 5) } animation: { _ in .easeInOut(duration:2.8) }
        }
    }
    private func phone(index:Int) -> some View {
        let shell = RoundedRectangle(cornerRadius:20).fill(.white.opacity(index == 0 ? 0.025 : 0.065)).frame(width:77,height:137)
            .overlay(alignment:.top) { Capsule().fill(.white.opacity(0.35)).frame(width:25,height:5).padding(.top,9) }
            .overlay(alignment:.bottom) { Capsule().fill(.white.opacity(0.3)).frame(width:26,height:3).padding(.bottom,8) }
            .overlay { Image(systemName:index == 0 ? "shippingbox" : complete ? "checkmark" : "app").font(.system(size:23,weight:.light)).foregroundStyle(.white.opacity(0.8)).contentTransition(.symbolEffect(.replace)) }
        return Group {
            if #available(iOS 26, *) { shell.glassEffect(.regular.tint(index == 0 ? .cyan.opacity(0.07) : relayTint.opacity(0.13)),in:.rect(cornerRadius:20)).glassEffectID(index,in:glass) }
            else { shell.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20)) }
        }.rotationEffect(.degrees(index == 0 ? -9 : 9)).offset(y:index == 0 ? 5 : -5)
    }
}
