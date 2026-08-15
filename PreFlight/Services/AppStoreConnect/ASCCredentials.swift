import Foundation

/// An App Store Connect API key: the two public identifiers plus the .p8
/// private key contents (which live in the Keychain, never in UserDefaults).
nonisolated struct ASCCredentials: Sendable {
    let issuerID: String
    let keyID: String
    let privateKeyPEM: String
}
