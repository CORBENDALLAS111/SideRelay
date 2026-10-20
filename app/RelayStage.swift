import Foundation

/// Raw strings are accepted only at the Rust event boundary.
enum RelayStage: String, Equatable, Sendable {
    case ready, validating, pairing, handshake, connecting, auth, signing, installing, installed, error
}
