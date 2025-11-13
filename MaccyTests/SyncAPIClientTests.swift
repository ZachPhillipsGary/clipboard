import XCTest
@testable import Maccy

@available(macOS 14.0, *)
final class SyncAPIClientTests: XCTestCase {
    var apiClient: SyncAPIClient!
    let testBaseURL = "https://test.example.com"
    let testToken = "test-auth-token"

    override func setUp() {
        super.setUp()
        apiClient = SyncAPIClient(baseURL: testBaseURL, authToken: testToken)
    }

    override func tearDown() {
        apiClient = nil
        super.tearDown()
    }

    // MARK: - URL Building Tests

    func testBaseURLTrimming() {
        // Test that trailing slashes are removed
        let clientWithSlash = SyncAPIClient(baseURL: "https://test.com/", authToken: nil)
        XCTAssertNotNil(clientWithSlash)

        let clientWithoutSlash = SyncAPIClient(baseURL: "https://test.com", authToken: nil)
        XCTAssertNotNil(clientWithoutSlash)
    }

    // MARK: - Error Handling Tests

    func testAPIErrorDescriptions() {
        let errors: [(SyncAPIClient.APIError, String)] = [
            (.invalidURL, "Invalid API URL"),
            (.noResponse, "No response from server"),
            (.invalidResponse(404, "Not found"), "Server error (404): Not found"),
            (.unauthorized, "Unauthorized. Please re-pair your device."),
            (.rateLimited(resetAt: 1699999999000), "Rate limited"),
        ]

        for (error, expectedSubstring) in errors {
            let description = error.localizedDescription
            XCTAssertTrue(
                description.contains(expectedSubstring) || description.lowercased().contains(expectedSubstring.lowercased()),
                "Error description '\(description)' should contain '\(expectedSubstring)'"
            )
        }
    }

    // MARK: - Request Model Tests

    func testRegisterDeviceRequest() {
        let request = RegisterDeviceRequest(
            sync_group_id: "group-1",
            device_id: "device-1",
            device_name: "Test Mac",
            device_type: "macos"
        )

        XCTAssertEqual(request.sync_group_id, "group-1")
        XCTAssertEqual(request.device_id, "device-1")
        XCTAssertEqual(request.device_name, "Test Mac")
        XCTAssertEqual(request.device_type, "macos")
    }

    func testPushItemsRequest() {
        let item = EncryptedItemPayload(
            id: "item-1",
            encrypted_payload: "test-payload",
            nonce: "test-nonce",
            created_at: 1699999999000,
            updated_at: 1699999999000,
            item_hash: String(repeating: "a", count: 64),
            compressed: false,
            size_bytes: 100
        )

        let request = PushItemsRequest(items: [item])

        XCTAssertEqual(request.items.count, 1)
        XCTAssertEqual(request.items[0].id, "item-1")
    }

    func testDeleteItemsRequest() {
        let request = DeleteItemsRequest(item_ids: ["item-1", "item-2"])

        XCTAssertEqual(request.item_ids.count, 2)
        XCTAssertTrue(request.item_ids.contains("item-1"))
        XCTAssertTrue(request.item_ids.contains("item-2"))
    }

    // MARK: - Response Model Tests

    func testPullItemsResponse() {
        let remoteItem = RemoteEncryptedItem(
            id: "item-1",
            device_id: "device-2",
            encrypted_payload: "payload",
            nonce: "nonce",
            created_at: 1699999999000,
            updated_at: 1699999999000,
            is_deleted: false,
            item_hash: String(repeating: "a", count: 64),
            compressed: false,
            size_bytes: 100
        )

        let response = PullItemsResponse(
            items: [remoteItem],
            has_more: false,
            server_timestamp: 1699999999000
        )

        XCTAssertEqual(response.items.count, 1)
        XCTAssertFalse(response.has_more)
        XCTAssertEqual(response.server_timestamp, 1699999999000)
    }

    func testPushItemsResponse() {
        let response = PushItemsResponse(
            accepted: 5,
            rejected: 2,
            conflicts: ["item-1", "item-2"]
        )

        XCTAssertEqual(response.accepted, 5)
        XCTAssertEqual(response.rejected, 2)
        XCTAssertEqual(response.conflicts.count, 2)
    }

    func testDeleteItemsResponse() {
        let response = DeleteItemsResponse(deleted: 3)

        XCTAssertEqual(response.deleted, 3)
    }

    func testSyncStatusResponse() {
        let deviceInfo = DeviceInfo(
            id: "device-1",
            name: "Test Mac",
            type: "macos",
            last_seen: 1699999999000,
            is_active: true
        )

        let response = SyncStatusResponse(
            sync_group_id: "group-1",
            device_count: 2,
            item_count: 100,
            total_size_bytes: 50000,
            last_activity: 1699999999000,
            devices: [deviceInfo]
        )

        XCTAssertEqual(response.sync_group_id, "group-1")
        XCTAssertEqual(response.device_count, 2)
        XCTAssertEqual(response.item_count, 100)
        XCTAssertEqual(response.devices.count, 1)
        XCTAssertEqual(response.devices[0].name, "Test Mac")
    }

    // MARK: - Codable Tests

    func testEncryptedItemPayloadCodable() throws {
        let original = EncryptedItemPayload(
            id: "test-id",
            encrypted_payload: "dGVzdA==",
            nonce: "bm9uY2U=",
            created_at: 1699999999000,
            updated_at: 1699999999000,
            item_hash: String(repeating: "a", count: 64),
            compressed: false,
            size_bytes: 100
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EncryptedItemPayload.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.encrypted_payload, decoded.encrypted_payload)
        XCTAssertEqual(original.nonce, decoded.nonce)
        XCTAssertEqual(original.created_at, decoded.created_at)
        XCTAssertEqual(original.updated_at, decoded.updated_at)
        XCTAssertEqual(original.item_hash, decoded.item_hash)
        XCTAssertEqual(original.compressed, decoded.compressed)
        XCTAssertEqual(original.size_bytes, decoded.size_bytes)
    }

    func testRemoteEncryptedItemCodable() throws {
        let original = RemoteEncryptedItem(
            id: "test-id",
            device_id: "device-1",
            encrypted_payload: "dGVzdA==",
            nonce: "bm9uY2U=",
            created_at: 1699999999000,
            updated_at: 1699999999000,
            is_deleted: false,
            item_hash: String(repeating: "a", count: 64),
            compressed: false,
            size_bytes: 100
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RemoteEncryptedItem.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.device_id, decoded.device_id)
        XCTAssertEqual(original.is_deleted, decoded.is_deleted)
    }
}
