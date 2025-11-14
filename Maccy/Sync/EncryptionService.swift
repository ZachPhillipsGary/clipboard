import Foundation
import CryptoKit
import OSLog

/// E2E encryption service using ChaCha20-Poly1305 AEAD
/// Handles encryption, decryption, and key management for clipboard sync
@available(macOS 14.0, *)
final class EncryptionService {
    // MARK: - Types

    enum EncryptionError: LocalizedError {
        case invalidKey
        case encryptionFailed
        case decryptionFailed
        case invalidNonce
        case invalidCiphertext
        case keyGenerationFailed
        case keychainError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidKey:
                return "Invalid encryption key"
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            case .invalidNonce:
                return "Invalid nonce"
            case .invalidCiphertext:
                return "Invalid ciphertext"
            case .keyGenerationFailed:
                return "Failed to generate encryption key"
            case .keychainError(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    struct EncryptedPayload {
        let ciphertext: Data
        let nonce: Data
        let hash: String
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "org.p0deje.Maccy", category: "EncryptionService")
    private let masterKey: SymmetricKey
    private static let nonceSize = 12 // ChaCha20-Poly1305 nonce size

    // Keychain constants
    private static let keychainService = "org.p0deje.Maccy.sync"
    private static let keychainAccount = "master-encryption-key"

    // MARK: - Initialization

    /// Initialize with existing master key
    init(masterKey: SymmetricKey) {
        self.masterKey = masterKey
    }

    /// Initialize by loading or generating master key
    convenience init() throws {
        if let existingKey = try? Self.loadMasterKeyFromKeychain() {
            self.init(masterKey: existingKey)
        } else {
            let newKey = Self.generateMasterKey()
            try Self.saveMasterKeyToKeychain(newKey)
            self.init(masterKey: newKey)
        }
    }

    // MARK: - Key Management

    /// Generate a new 256-bit master key
    static func generateMasterKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }

    /// Save master key to macOS Keychain
    static func saveMasterKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false // Don't sync via iCloud
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status)
        }
    }

    /// Load master key from macOS Keychain
    static func loadMasterKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let keyData = item as? Data else {
            throw EncryptionError.keychainError(status)
        }

        return SymmetricKey(data: keyData)
    }

    /// Delete master key from Keychain (use with caution!)
    static func deleteMasterKeyFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status)
        }
    }

    /// Export master key as base64 (for QR code)
    func exportMasterKeyBase64() -> String {
        return masterKey.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Import master key from base64
    static func importMasterKeyFromBase64(_ base64String: String) throws -> SymmetricKey {
        guard let keyData = Data(base64Encoded: base64String),
              keyData.count == 32 else {
            throw EncryptionError.invalidKey
        }
        return SymmetricKey(data: keyData)
    }

    // MARK: - Encryption

    /// Encrypt data using ChaCha20-Poly1305
    func encrypt(_ plaintext: Data) throws -> EncryptedPayload {
        // Generate random nonce
        var nonceBytes = [UInt8](repeating: 0, count: Self.nonceSize)
        let result = SecRandomCopyBytes(kSecRandomDefault, Self.nonceSize, &nonceBytes)
        guard result == errSecSuccess else {
            logger.error("Failed to generate nonce: \(result)")
            throw EncryptionError.encryptionFailed
        }

        let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

        // Encrypt with AEAD
        let sealedBox: ChaChaPoly.SealedBox
        do {
            sealedBox = try ChaChaPoly.seal(plaintext, using: masterKey, nonce: nonce)
        } catch {
            logger.error("Encryption failed: \(error.localizedDescription)")
            throw EncryptionError.encryptionFailed
        }

        // Calculate SHA-256 hash of plaintext (for deduplication)
        let hash = SHA256.hash(data: plaintext)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return EncryptedPayload(
            ciphertext: sealedBox.ciphertext + sealedBox.tag,
            nonce: Data(nonceBytes),
            hash: hashString
        )
    }

    /// Encrypt JSON encodable data
    func encryptJSON<T: Encodable>(_ value: T) throws -> EncryptedPayload {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(value)
        return try encrypt(jsonData)
    }

    // MARK: - Decryption

    /// Decrypt data using ChaCha20-Poly1305
    func decrypt(ciphertext: Data, nonce: Data) throws -> Data {
        // Validate nonce
        guard nonce.count == Self.nonceSize else {
            logger.error("Invalid nonce size: \(nonce.count)")
            throw EncryptionError.invalidNonce
        }

        // ChaCha20-Poly1305 has 16-byte authentication tag
        guard ciphertext.count >= 16 else {
            logger.error("Ciphertext too short: \(ciphertext.count)")
            throw EncryptionError.invalidCiphertext
        }

        // Split ciphertext and tag
        let actualCiphertext = ciphertext.prefix(ciphertext.count - 16)
        let tag = ciphertext.suffix(16)

        // Create nonce
        let chaChaNonce: ChaChaPoly.Nonce
        do {
            chaChaNonce = try ChaChaPoly.Nonce(data: nonce)
        } catch {
            logger.error("Failed to create nonce: \(error.localizedDescription)")
            throw EncryptionError.invalidNonce
        }

        // Create sealed box
        let sealedBox: ChaChaPoly.SealedBox
        do {
            sealedBox = try ChaChaPoly.SealedBox(nonce: chaChaNonce, ciphertext: actualCiphertext, tag: tag)
        } catch {
            logger.error("Failed to create sealed box: \(error.localizedDescription)")
            throw EncryptionError.invalidCiphertext
        }

        // Decrypt
        do {
            return try ChaChaPoly.open(sealedBox, using: masterKey)
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription)")
            throw EncryptionError.decryptionFailed
        }
    }

    /// Decrypt to JSON decodable type
    func decryptJSON<T: Decodable>(ciphertext: Data, nonce: Data, type: T.Type) throws -> T {
        let plaintext = try decrypt(ciphertext: ciphertext, nonce: nonce)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(type, from: plaintext)
    }

    // MARK: - Utilities

    /// Verify hash matches plaintext
    func verifyHash(_ plaintext: Data, expectedHash: String) -> Bool {
        let hash = SHA256.hash(data: plaintext)
        let actualHash = hash.compactMap { String(format: "%02x", $0) }.joined()
        return actualHash == expectedHash
    }

    /// Calculate SHA-256 hash
    static func calculateHash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
