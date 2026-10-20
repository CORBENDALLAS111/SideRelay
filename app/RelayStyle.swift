import SwiftUI

let relayTint = Color(red:0.52,green:0.91,blue:0.86)

enum RelayBuild {
    static var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—" }
}
