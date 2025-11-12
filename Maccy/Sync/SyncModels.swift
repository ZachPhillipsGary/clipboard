import Foundation

// MARK: - Sync Configuration

struct SyncConfiguration: Codable {
    let version: Int
    let syncGroupId: String
    let masterKey: String // base64
    let apiEndpoint: String
    let deviceId: String

    init(version: Int = 1, syncGroupId: String, masterKey: String, apiEndpoint: String, deviceId: String) {
        self.version = version
        self.syncGroupId = syncGroupId
        self.masterKey = masterKey
        self.apiEndpoint = apiEndpoint
        self.deviceId = deviceId
    }
}

// MARK: - API Request/Response Models

struct RegisterDeviceRequest: Codable {
    let sync_group_id: String
    let device_id: String
    let device_name: String
    let device_type: String
}

struct RegisterDeviceResponse: Codable {
    let token: String
    let sync_group: SyncGroup
    let device: Device
}

struct SyncGroup: Codable {
    let id: String
    let created_at: Int64
    let last_activity: Int64
}

struct Device: Codable {
    let id: String
    let sync_group_id: String
    let device_name: String
    let device_type: String
    let registered_at: Int64
    let last_seen: Int64
    let is_active: Int
}

struct PushItemsRequest: Codable {
    let items: [EncryptedItemPayload]
}

struct EncryptedItemPayload: Codable {
    let id: String
    let encrypted_payload: String // base64
    let nonce: String // base64
    let created_at: Int64
    let updated_at: Int64
    let item_hash: String
    let compressed: Bool
    let size_bytes: Int
}

struct PushItemsResponse: Codable {
    let accepted: Int
    let rejected: Int
    let conflicts: [String]
}

struct PullItemsResponse: Codable {
    let items: [RemoteEncryptedItem]
    let has_more: Bool
    let server_timestamp: Int64
}

struct RemoteEncryptedItem: Codable {
    let id: String
    let device_id: String
    let encrypted_payload: String // base64
    let nonce: String // base64
    let created_at: Int64
    let updated_at: Int64
    let is_deleted: Bool
    let item_hash: String
    let compressed: Bool
    let size_bytes: Int
}

struct DeleteItemsRequest: Codable {
    let item_ids: [String]
}

struct DeleteItemsResponse: Codable {
    let deleted: Int
}

struct SyncStatusResponse: Codable {
    let sync_group_id: String
    let device_count: Int
    let item_count: Int
    let total_size_bytes: Int64
    let last_activity: Int64
    let devices: [DeviceInfo]
}

struct DeviceInfo: Codable {
    let id: String
    let name: String
    let type: String
    let last_seen: Int64
    let is_active: Bool
}

struct ErrorResponse: Codable {
    let error: String
    let code: String
    let details: AnyCodable?
}

// Helper for any JSON type
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Serializable HistoryItem

/// Serializable version of HistoryItem for encryption
struct SerializableHistoryItem: Codable {
    let id: String?
    let application: String?
    let firstCopiedAt: Date
    let lastCopiedAt: Date
    let numberOfCopies: Int
    let pin: String?
    let title: String
    let contents: [SerializableHistoryItemContent]

    // Sync metadata
    let syncId: String
    let deviceId: String

    init(from historyItem: HistoryItem, syncId: String, deviceId: String) {
        // Note: HistoryItem uses SwiftData @Model, may not have direct id access
        // We'll use syncId as primary identifier for sync purposes
        self.id = syncId
        self.application = historyItem.application
        self.firstCopiedAt = historyItem.firstCopiedAt
        self.lastCopiedAt = historyItem.lastCopiedAt
        self.numberOfCopies = historyItem.numberOfCopies
        self.pin = historyItem.pin
        self.title = historyItem.title
        self.contents = historyItem.contents.map { SerializableHistoryItemContent(from: $0) }
        self.syncId = syncId
        self.deviceId = deviceId
    }
}

struct SerializableHistoryItemContent: Codable {
    let type: String
    let value: Data?

    init(from content: HistoryItemContent) {
        self.type = content.type
        self.value = content.value
    }
}

// MARK: - Sync Metadata Extensions

extension HistoryItem {
    /// Get or create sync ID for this item
    func getSyncId() -> String {
        // Try to get from persistent storage if we add a syncId property
        // For now, generate based on content hash
        return UUID().uuidString
    }

    /// Generate content hash for deduplication
    func generateContentHash() -> String {
        var hashData = Data()

        // Hash title
        if let titleData = title.data(using: .utf8) {
            hashData.append(titleData)
        }

        // Hash all content types and values
        for content in contents {
            if let typeData = content.type.data(using: .utf8) {
                hashData.append(typeData)
            }
            if let value = content.value {
                hashData.append(value)
            }
        }

        return EncryptionService.calculateHash(hashData)
    }
}
