import SwiftUI

@main
struct SideRelayApp: App {
    @State private var model = RelayModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RelayView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in
                    if value == .background && model.busy { model.cancel() }
                }
        }
    }
}
