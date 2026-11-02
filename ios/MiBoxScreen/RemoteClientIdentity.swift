// Adapted from Open Source TV Remote, Copyright (c) 2026 Nathan Butler, MIT License.
import Foundation
import Security

enum RemoteClientIdentity {
    struct Material { let identity: SecIdentity; let certificate: SecCertificate }
    enum IdentityError: LocalizedError {
        case setup(String)
        var errorDescription: String? { if case .setup(let text) = self { return "Nie udało się utworzyć klucza pilota: \(text)" }; return nil }
    }

    private static let label = "MiBox Screen Android TV Remote"
    private static let keyTag = Data("pl.miboxscreen.ios.remote-key".utf8)
    private static var cached: Material?

    static func loadOrCreate() throws -> Material {
        if let cached { return cached }
        if let found = find() { cached = found; return found }
        try create()
        guard let found = find() else { throw IdentityError.setup("brak tożsamości po utworzeniu") }
        cached = found
        return found
    }

    private static func find() -> Material? {
        let query: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity] else { return nil }
        for identity in identities {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
               let certificate,
               SecCertificateCopySubjectSummary(certificate) as String? == label {
                return Material(identity: identity, certificate: certificate)
            }
        }
        return nil
    }

    private static func create() throws {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: keyTag]
        ]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw IdentityError.setup(error?.takeRetainedValue().localizedDescription ?? "generowanie RSA")
        }
        let algorithm = RemoteDER.sequence([RemoteDER.oid("1.2.840.113549.1.1.11"), RemoteDER.null])
        let name = RemoteDER.sequence([RemoteDER.set([RemoteDER.sequence([RemoteDER.oid("2.5.4.3"), RemoteDER.utf8(label)])])])
        let validity = RemoteDER.sequence([RemoteDER.time(Date().addingTimeInterval(-86400)), RemoteDER.time(Date().addingTimeInterval(20 * 365 * 86400))])
        let publicInfo = RemoteDER.sequence([RemoteDER.sequence([RemoteDER.oid("1.2.840.113549.1.1.1"), RemoteDER.null]), RemoteDER.bitString(Array(publicData))])
        var serial = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7f
        let body = RemoteDER.sequence([RemoteDER.explicit(0, RemoteDER.integer(2)), RemoteDER.integer(serial), algorithm, name, validity, name, publicInfo])
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(body) as CFData, &error) as Data? else {
            throw IdentityError.setup(error?.takeRetainedValue().localizedDescription ?? "podpis certyfikatu")
        }
        let certificateData = RemoteDER.sequence([body, algorithm, RemoteDER.bitString(Array(signature))])
        guard let certificate = SecCertificateCreateWithData(nil, Data(certificateData) as CFData) else { throw IdentityError.setup("certyfikat") }
        let status = SecItemAdd([kSecClass as String: kSecClassCertificate, kSecValueRef as String: certificate, kSecAttrLabel as String: label] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw IdentityError.setup("OSStatus \(status)") }
    }
}
