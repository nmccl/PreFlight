import CryptoKit
import Foundation

/// Signs ES256 JWTs for the App Store Connect API using CryptoKit — no
/// third-party JWT dependency needed.
nonisolated struct ASCJWTSigner: Sendable {
    private struct Header: Encodable {
        let alg = "ES256"
        let kid: String
        let typ = "JWT"
    }

    private struct Payload: Encodable {
        let iss: String
        let iat: Int
        let exp: Int
        let aud = "appstoreconnect-v1"
    }

    func token(for credentials: ASCCredentials, now: Date = .now) throws -> String {
        let header = Header(kid: credentials.keyID)
        // ASC rejects tokens valid longer than 20 minutes; use 15 to be safe.
        let payload = Payload(
            iss: credentials.issuerID,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(now.addingTimeInterval(15 * 60).timeIntervalSince1970)
        )

        let signingInput = try base64URL(JSONEncoder().encode(header))
            + "."
            + base64URL(JSONEncoder().encode(payload))

        // The .p8 file from App Store Connect is PKCS#8 PEM, which CryptoKit
        // parses directly. rawRepresentation is the 64-byte r||s form JWT
        // requires (not DER).
        let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        let signature = try key.signature(for: Data(signingInput.utf8))

        return signingInput + "." + base64URL(signature.rawRepresentation)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
