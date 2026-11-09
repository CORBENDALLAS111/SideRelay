import SwiftUI

let relayTint = Color(white:0.86)

enum RelayBuild {
    static var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—" }
}
