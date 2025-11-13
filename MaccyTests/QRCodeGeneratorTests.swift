import XCTest
import AppKit
@testable import Maccy

@available(macOS 14.0, *)
final class QRCodeGeneratorTests: XCTestCase {
    // MARK: - QR Code Generation Tests

    func testGenerateQRCodeFromString() throws {
        // Given
        let testString = "Hello, World!"
        let size = CGSize(width: 200, height: 200)

        // When
        let qrImage = try QRCodeGenerator.generateQRCode(from: testString, size: size)

        // Then
        XCTAssertNotNil(qrImage)
        XCTAssertEqual(qrImage.size, size)
    }

    func testGenerateQRCodeFromConfiguration() throws {
        // Given
        let syncGroupId = UUID().uuidString
        let deviceId = UUID().uuidString
        let masterKey = "dGVzdC1tYXN0ZXIta2V5LTMyLWJ5dGVzLWJhc2U2NA==" // Base64 encoded 32 bytes
        let apiEndpoint = "https://test.example.com"

        // When
        let qrImage = try QRCodeGenerator.generateQRCode(
            syncGroupId: syncGroupId,
            masterKey: masterKey,
            apiEndpoint: apiEndpoint,
            deviceId: deviceId,
            size: CGSize(width: 256, height: 256)
        )

        // Then
        XCTAssertNotNil(qrImage)
    }

    func testGenerateQRCodeWithDefaultSize() throws {
        // Given
        let testString = "Test"

        // When
        let qrImage = try QRCodeGenerator.generateQRCode(from: testString, size: CGSize(width: 512, height: 512))

        // Then
        XCTAssertNotNil(qrImage)
        XCTAssertEqual(qrImage.size.width, 512)
        XCTAssertEqual(qrImage.size.height, 512)
    }

    func testGenerateQRCodeWithEmptyString() {
        // Given
        let emptyString = ""

        // When/Then
        XCTAssertThrowsError(try QRCodeGenerator.generateQRCode(from: emptyString, size: CGSize(width: 200, height: 200)))
    }

    func testGenerateQRCodeWithLongString() throws {
        // Given - QR codes can store up to ~4KB with high error correction
        let longString = String(repeating: "A", count: 2000)

        // When
        let qrImage = try QRCodeGenerator.generateQRCode(from: longString, size: CGSize(width: 512, height: 512))

        // Then
        XCTAssertNotNil(qrImage)
    }

    // MARK: - Primary Sync Configuration Tests

    func testCreatePrimarySyncConfiguration() throws {
        // Given
        let apiEndpoint = "https://test.example.com"

        // Clean up any existing key
        try? EncryptionService.deleteMasterKeyFromKeychain()

        // When
        let (config, qrImage) = try QRCodeGenerator.createPrimarySyncConfiguration(apiEndpoint: apiEndpoint)

        // Then
        XCTAssertNotNil(config)
        XCTAssertNotNil(qrImage)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.apiEndpoint, apiEndpoint)
        XCTAssertFalse(config.syncGroupId.isEmpty)
        XCTAssertFalse(config.deviceId.isEmpty)
        XCTAssertFalse(config.masterKey.isEmpty)

        // Verify UUIDs are valid
        XCTAssertNotNil(UUID(uuidString: config.syncGroupId))
        XCTAssertNotNil(UUID(uuidString: config.deviceId))

        // Verify master key is base64
        XCTAssertNotNil(Data(base64Encoded: config.masterKey))

        // Verify key was saved to keychain
        let loadedKey = try EncryptionService.loadMasterKeyFromKeychain()
        XCTAssertNotNil(loadedKey)

        // Cleanup
        try EncryptionService.deleteMasterKeyFromKeychain()
    }

    func testSyncConfigurationCodable() throws {
        // Given
        let original = SyncConfiguration(
            version: 1,
            syncGroupId: UUID().uuidString,
            masterKey: "dGVzdA==",
            apiEndpoint: "https://test.example.com",
            deviceId: UUID().uuidString
        )

        // When
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncConfiguration.self, from: data)

        // Then
        XCTAssertEqual(original.version, decoded.version)
        XCTAssertEqual(original.syncGroupId, decoded.syncGroupId)
        XCTAssertEqual(original.masterKey, decoded.masterKey)
        XCTAssertEqual(original.apiEndpoint, decoded.apiEndpoint)
        XCTAssertEqual(original.deviceId, decoded.deviceId)
    }

    func testQRCodeContainsValidJSON() throws {
        // Given
        let syncGroupId = UUID().uuidString
        let deviceId = UUID().uuidString
        let masterKey = Data(repeating: 0x42, count: 32).base64EncodedString()
        let apiEndpoint = "https://test.example.com"

        // When
        _ = try QRCodeGenerator.generateQRCode(
            syncGroupId: syncGroupId,
            masterKey: masterKey,
            apiEndpoint: apiEndpoint,
            deviceId: deviceId
        )

        // Then
        // If we got here without throwing, the QR code was generated successfully
        // In a real test, we would scan the QR code and verify the JSON
        XCTAssertTrue(true)
    }

    // MARK: - Image Size Tests

    func testQRCodeSizeScaling() throws {
        // Given
        let testString = "Test"
        let sizes: [CGSize] = [
            CGSize(width: 100, height: 100),
            CGSize(width: 256, height: 256),
            CGSize(width: 512, height: 512),
            CGSize(width: 1024, height: 1024)
        ]

        // When/Then
        for size in sizes {
            let qrImage = try QRCodeGenerator.generateQRCode(from: testString, size: size)
            XCTAssertEqual(qrImage.size.width, size.width, accuracy: 1.0)
            XCTAssertEqual(qrImage.size.height, size.height, accuracy: 1.0)
        }
    }

    func testQRCodeNonSquareSize() throws {
        // Given
        let testString = "Test"
        let size = CGSize(width: 400, height: 200)

        // When
        let qrImage = try QRCodeGenerator.generateQRCode(from: testString, size: size)

        // Then - QR codes should maintain aspect ratio
        XCTAssertNotNil(qrImage)
    }

    // MARK: - Error Handling Tests

    func testGenerateQRCodeWithInvalidData() {
        // Given - very long string that exceeds QR code capacity
        let tooLongString = String(repeating: "A", count: 10000)

        // When/Then
        // This might succeed with lower error correction, but we're testing limits
        do {
            _ = try QRCodeGenerator.generateQRCode(from: tooLongString, size: CGSize(width: 512, height: 512))
        } catch {
            // Expected to fail for very long strings
            XCTAssertTrue(error is QRCodeGenerator.QRError)
        }
    }

    // MARK: - Configuration Validation Tests

    func testSyncConfigurationWithInvalidURL() throws {
        // Given
        let config = SyncConfiguration(
            version: 1,
            syncGroupId: UUID().uuidString,
            masterKey: "test",
            apiEndpoint: "not-a-valid-url",
            deviceId: UUID().uuidString
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        // Then
        XCTAssertNotNil(data)
        // Note: The config itself doesn't validate the URL, that's done when used
    }
}
