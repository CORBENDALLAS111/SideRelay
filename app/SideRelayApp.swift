import SwiftUI

@main
struct SideRelayApp: App {
    @State private var model = RelayModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RelayView(model: model)
                #if DEBUG
                .modifier(RelayPreviewType())
                #endif
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in
                    if value == .background { model.enterBackground() }
                    if value == .active { model.endBackground() }
                }
        }
    }
}
