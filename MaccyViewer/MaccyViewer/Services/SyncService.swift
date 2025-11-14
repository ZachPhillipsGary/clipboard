import Foundation
import CryptoKit

/// iOS-specific sync service
/// Handles pulling and decrypting clipboard items from the server
@MainActor
class SyncService: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var lastSyncTime: Date?
    @Published var items: [ClipboardItem] = []

    private var encryptionService: EncryptionService?
    private var apiClient: SyncAPIClient?

    private var syncGroupId: String?
    private var deviceId: String?
    private var authToken: String?
    private var apiEndpoint: String?

    init() {
        loadConfiguration()
    }

    // MARK: - Configuration

    func configure(with config: SyncConfiguration) throws {
        // Import and save master key
        let masterKey = try EncryptionService.importMasterKeyFromBase64(config.masterKey)
        try EncryptionService.saveMasterKeyToKeychain(masterKey)

        // Create encryption service
        self.encryptionService = EncryptionService(masterKey: masterKey)

        // Store configuration
        self.syncGroupId = config.syncGroupId
        self.deviceId = config.deviceId
        self.apiEndpoint = config.apiEndpoint

        UserDefaults.standard.set(config.syncGroupId, forKey: "syncGroupId")
        UserDefaults.standard.set(config.deviceId, forKey: "syncDeviceId")
        UserDefaults.standard.set(config.apiEndpoint, forKey: "syncApiEndpoint")

        // Register device
        Task {
            try await registerDevice()
        }
    }

    private func loadConfiguration() {
        guard let savedGroupId = UserDefaults.standard.string(forKey: "syncGroupId"),
              let savedDeviceId = UserDefaults.standard.string(forKey: "syncDeviceId"),
              let savedApiEndpoint = UserDefaults.standard.string(forKey: "syncApiEndpoint"),
              let savedAuthToken = UserDefaults.standard.string(forKey: "syncAuthToken") else {
            return
        }

        self.syncGroupId = savedGroupId
        self.deviceId = savedDeviceId
        self.apiEndpoint = savedApiEndpoint
        self.authToken = savedAuthToken

        // Initialize services
        do {
            self.encryptionService = try EncryptionService()
            self.apiClient = SyncAPIClient(baseURL: savedApiEndpoint, authToken: savedAuthToken)
            self.isEnabled = true
        } catch {
            print("Failed to initialize encryption service: \(error)")
        }
    }

    // MARK: - Device Registration

    private func registerDevice() async throws {
        guard let syncGroupId = syncGroupId,
              let deviceId = deviceId,
              let apiEndpoint = apiEndpoint else {
            throw NSError(domain: "SyncService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Missing configuration"
            ])
        }

        let tempClient = SyncAPIClient(baseURL: apiEndpoint)
        let deviceName = UIDevice.current.name

        let response = try await tempClient.registerDevice(
            syncGroupId: syncGroupId,
            deviceId: deviceId,
            deviceName: deviceName,
            deviceType: "ios"
        )

        // Save auth token
        self.authToken = response.token
        UserDefaults.standard.set(response.token, forKey: "syncAuthToken")

        // Create API client with auth
        self.apiClient = SyncAPIClient(baseURL: apiEndpoint, authToken: response.token)
        self.isEnabled = true
    }

    // MARK: - Sync

    func performSync() async throws {
        guard let encryptionService = encryptionService,
              let apiClient = apiClient else {
            throw NSError(domain: "SyncService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Sync not configured"
            ])
        }

        // Get last sync timestamp
        let lastTimestamp = UserDefaults.standard.object(forKey: "lastSyncTimestamp") as? Int64 ?? 0

        // Pull items from server
        let response = try await apiClient.pullItems(since: lastTimestamp, limit: 100)

        var decryptedItems: [ClipboardItem] = []

        // Decrypt items
        for remoteItem in response.items {
            guard !remoteItem.is_deleted else { continue }

            guard let ciphertext = Data(base64Encoded: remoteItem.encrypted_payload),
                  let nonce = Data(base64Encoded: remoteItem.nonce) else {
                print("Invalid base64 data for item \(remoteItem.id)")
                continue
            }

            do {
                let serializable = try encryptionService.decryptJSON(
                    ciphertext: ciphertext,
                    nonce: nonce,
                    type: SerializableHistoryItem.self
                )

                let item = ClipboardItem(from: serializable)
                decryptedItems.append(item)
            } catch {
                print("Failed to decrypt item: \(error)")
                continue
            }
        }

        // Update items and timestamp
        self.items = decryptedItems
        self.lastSyncTime = Date()

        UserDefaults.standard.set(response.server_timestamp, forKey: "lastSyncTimestamp")
    }

    func getStatus() async throws -> SyncStatusResponse {
        guard let apiClient = apiClient else {
            throw NSError(domain: "SyncService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Sync not configured"
            ])
        }

        return try await apiClient.getStatus()
    }

    // MARK: - Cleanup

    func clearSyncData() {
        // Clear keychain
        try? EncryptionService.deleteMasterKeyFromKeychain()

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "syncGroupId")
        UserDefaults.standard.removeObject(forKey: "syncDeviceId")
        UserDefaults.standard.removeObject(forKey: "syncApiEndpoint")
        UserDefaults.standard.removeObject(forKey: "syncAuthToken")
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")

        // Clear state
        syncGroupId = nil
        deviceId = nil
        authToken = nil
        apiEndpoint = nil
        encryptionService = nil
        apiClient = nil
        items = []
        lastSyncTime = nil
        isEnabled = false
    }
}

// Copy the SyncConfiguration, EncryptionService, and SyncAPIClient from macOS
// (These should ideally be in a shared Swift package)

// For now, we'll include minimal versions here:

struct SyncConfiguration: Codable {
    let version: Int
    let syncGroupId: String
    let masterKey: String
    let apiEndpoint: String
    let deviceId: String
}

// Re-use EncryptionService from macOS (copy implementation)
final class EncryptionService {
    enum EncryptionError: LocalizedError {
        case invalidKey
        case encryptionFailed
        case decryptionFailed
        case invalidNonce
        case invalidCiphertext
        case keychainError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidKey: return "Invalid encryption key"
            case .encryptionFailed: return "Failed to encrypt data"
            case .decryptionFailed: return "Failed to decrypt data"
            case .invalidNonce: return "Invalid nonce"
            case .invalidCiphertext: return "Invalid ciphertext"
            case .keychainError(let status): return "Keychain error: \(status)"
            }
        }
    }

    private let masterKey: SymmetricKey
    private static let nonceSize = 12

    private static let keychainService = "org.p0deje.MaccyViewer.sync"
    private static let keychainAccount = "master-encryption-key"

    init(masterKey: SymmetricKey) {
        self.masterKey = masterKey
    }

    convenience init() throws {
        if let existingKey = try? Self.loadMasterKeyFromKeychain() {
            self.init(masterKey: existingKey)
        } else {
            throw EncryptionError.invalidKey
        }
    }

    static func saveMasterKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status)
        }
    }

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

        guard status == errSecSuccess, let keyData = item as? Data else {
            throw EncryptionError.keychainError(status)
        }

        return SymmetricKey(data: keyData)
    }

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

    static func importMasterKeyFromBase64(_ base64String: String) throws -> SymmetricKey {
        guard let keyData = Data(base64Encoded: base64String), keyData.count == 32 else {
            throw EncryptionError.invalidKey
        }
        return SymmetricKey(data: keyData)
    }

    func decryptJSON<T: Decodable>(ciphertext: Data, nonce: Data, type: T.Type) throws -> T {
        let plaintext = try decrypt(ciphertext: ciphertext, nonce: nonce)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: plaintext)
    }

    private func decrypt(ciphertext: Data, nonce: Data) throws -> Data {
        guard nonce.count == Self.nonceSize else {
            throw EncryptionError.invalidNonce
        }

        guard ciphertext.count >= 16 else {
            throw EncryptionError.invalidCiphertext
        }

        let actualCiphertext = ciphertext.prefix(ciphertext.count - 16)
        let tag = ciphertext.suffix(16)

        let chaChaNonce = try ChaChaPoly.Nonce(data: nonce)
        let sealedBox = try ChaChaPoly.SealedBox(nonce: chaChaNonce, ciphertext: actualCiphertext, tag: tag)

        return try ChaChaPoly.open(sealedBox, using: masterKey)
    }
}

// Include necessary API models
struct SerializableHistoryItem: Codable {
    let id: String?
    let application: String?
    let firstCopiedAt: Date
    let lastCopiedAt: Date
    let numberOfCopies: Int
    let pin: String?
    let title: String
    let contents: [SerializableHistoryItemContent]
    let syncId: String
    let deviceId: String
}

struct SerializableHistoryItemContent: Codable {
    let type: String
    let value: Data?
}
