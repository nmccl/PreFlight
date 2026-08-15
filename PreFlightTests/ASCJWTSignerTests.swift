import CryptoKit
import Foundation
import Testing
@testable import PreFlight

@Suite("ASC JWT signer")
struct ASCJWTSignerTests {
    private func makeCredentials(key: P256.Signing.PrivateKey) -> ASCCredentials {
        ASCCredentials(
            issuerID: "issuer-123",
            keyID: "KEY123",
            privateKeyPEM: key.pemRepresentation
        )
    }

    @Test("Token has three base64url segments with the expected claims")
    func tokenStructure() throws {
        let key = P256.Signing.PrivateKey()
        let token = try ASCJWTSigner().token(for: makeCredentials(key: key))
        let segments = token.split(separator: ".")
        #expect(segments.count == 3)

        let header = try #require(decodeJSON(String(segments[0])))
        #expect(header["alg"] as? String == "ES256")
        #expect(header["kid"] as? String == "KEY123")
        #expect(header["typ"] as? String == "JWT")

        let payload = try #require(decodeJSON(String(segments[1])))
        #expect(payload["iss"] as? String == "issuer-123")
        #expect(payload["aud"] as? String == "appstoreconnect-v1")

        let issuedAt = try #require(payload["iat"] as? Int)
        let expires = try #require(payload["exp"] as? Int)
        #expect(expires - issuedAt == 15 * 60)
    }

    @Test("Signature verifies with the key's public half")
    func signatureVerifies() throws {
        let key = P256.Signing.PrivateKey()
        let token = try ASCJWTSigner().token(for: makeCredentials(key: key))
        let segments = token.split(separator: ".").map(String.init)

        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let signatureData = try #require(base64URLDecode(segments[2]))
        // rawRepresentation is the 64-byte r||s form JWT requires.
        #expect(signatureData.count == 64)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        #expect(key.publicKey.isValidSignature(signature, for: signingInput))
    }

    @Test("Garbage PEM throws instead of producing a token")
    func invalidKeyThrows() {
        let credentials = ASCCredentials(
            issuerID: "issuer-123",
            keyID: "KEY123",
            privateKeyPEM: "not a pem"
        )
        #expect(throws: (any Error).self) {
            try ASCJWTSigner().token(for: credentials)
        }
    }

    // MARK: Helpers

    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }

    private func decodeJSON(_ segment: String) -> [String: Any]? {
        guard let data = base64URLDecode(segment) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
