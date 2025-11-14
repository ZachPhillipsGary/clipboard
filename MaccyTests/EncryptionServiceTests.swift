import XCTest
import CryptoKit
@testable import Maccy

@available(macOS 14.0, *)
final class EncryptionServiceTests: XCTestCase {
    var encryptionService: EncryptionService!

    override func setUp() {
        super.setUp()
        // Create encryption service with test key
        let testKey = SymmetricKey(size: .bits256)
        encryptionService = EncryptionService(masterKey: testKey)
    }

    override func tearDown() {
        encryptionService = nil
        super.tearDown()
    }

    // MARK: - Encryption/Decryption Tests

    func testEncryptDecryptRoundtrip() throws {
        // Given
        let plaintext = "Hello, World! This is a test message.".data(using: .utf8)!

        // When
        let encrypted = try encryptionService.encrypt(plaintext)
        let decrypted = try encryptionService.decrypt(ciphertext: encrypted.ciphertext, nonce: encrypted.nonce)

        // Then
        XCTAssertEqual(plaintext, decrypted)
    }

    func testEncryptProducesUniqueNonces() throws {
        // Given
        let plaintext = "Test message".data(using: .utf8)!

        // When
        let encrypted1 = try encryptionService.encrypt(plaintext)
        let encrypted2 = try encryptionService.encrypt(plaintext)

        // Then
        XCTAssertNotEqual(encrypted1.nonce, encrypted2.nonce)
        XCTAssertNotEqual(encrypted1.ciphertext, encrypted2.ciphertext)
    }

    func testEncryptJSONRoundtrip() throws {
        // Given
        struct TestData: Codable, Equatable {
            let name: String
            let count: Int
            let timestamp: Date
        }

        let original = TestData(
            name: "Test",
            count: 42,
            timestamp: Date()
        )

        // When
        let encrypted = try encryptionService.encryptJSON(original)
        let decrypted = try encryptionService.decryptJSON(
            ciphertext: encrypted.ciphertext,
            nonce: encrypted.nonce,
            type: TestData.self
        )

        // Then
        XCTAssertEqual(original.name, decrypted.name)
        XCTAssertEqual(original.count, decrypted.count)
        // Allow small time difference for Date encoding/decoding
        XCTAssertEqual(original.timestamp.timeIntervalSince1970,
                       decrypted.timestamp.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testDecryptWithWrongNonceFails() throws {
        // Given
        let plaintext = "Test message".data(using: .utf8)!
        let encrypted = try encryptionService.encrypt(plaintext)
        let wrongNonce = Data(repeating: 0, count: 12)

        // When/Then
        XCTAssertThrowsError(try encryptionService.decrypt(
            ciphertext: encrypted.ciphertext,
            nonce: wrongNonce
        )) { error in
            XCTAssertTrue(error is EncryptionService.EncryptionError)
        }
    }

    func testDecryptWithTamperedCiphertextFails() throws {
        // Given
        let plaintext = "Test message".data(using: .utf8)!
        let encrypted = try encryptionService.encrypt(plaintext)

        // Tamper with ciphertext
        var tamperedCiphertext = encrypted.ciphertext
        tamperedCiphertext[0] ^= 0xFF

        // When/Then
        XCTAssertThrowsError(try encryptionService.decrypt(
            ciphertext: tamperedCiphertext,
            nonce: encrypted.nonce
        )) { error in
            XCTAssertTrue(error is EncryptionService.EncryptionError)
        }
    }

    func testEncryptEmptyData() throws {
        // Given
        let plaintext = Data()

        // When
        let encrypted = try encryptionService.encrypt(plaintext)
        let decrypted = try encryptionService.decrypt(ciphertext: encrypted.ciphertext, nonce: encrypted.nonce)

        // Then
        XCTAssertEqual(plaintext, decrypted)
    }

    func testEncryptLargeData() throws {
        // Given
        let plaintext = Data(repeating: 0x42, count: 1_000_000) // 1MB

        // When
        let encrypted = try encryptionService.encrypt(plaintext)
        let decrypted = try encryptionService.decrypt(ciphertext: encrypted.ciphertext, nonce: encrypted.nonce)

        // Then
        XCTAssertEqual(plaintext, decrypted)
    }

    // MARK: - Hash Tests

    func testHashGenerationConsistent() throws {
        // Given
        let data = "Test data".data(using: .utf8)!

        // When
        let encrypted1 = try encryptionService.encrypt(data)
        let encrypted2 = try encryptionService.encrypt(data)

        // Then
        XCTAssertEqual(encrypted1.hash, encrypted2.hash)
    }

    func testHashVerification() throws {
        // Given
        let plaintext = "Test message".data(using: .utf8)!
        let encrypted = try encryptionService.encrypt(plaintext)

        // When
        let isValid = encryptionService.verifyHash(plaintext, expectedHash: encrypted.hash)

        // Then
        XCTAssertTrue(isValid)
    }

    func testHashVerificationWithWrongData() throws {
        // Given
        let plaintext = "Test message".data(using: .utf8)!
        let encrypted = try encryptionService.encrypt(plaintext)
        let wrongData = "Wrong message".data(using: .utf8)!

        // When
        let isValid = encryptionService.verifyHash(wrongData, expectedHash: encrypted.hash)

        // Then
        XCTAssertFalse(isValid)
    }

    // MARK: - Key Management Tests

    func testMasterKeyGeneration() {
        // When
        let key = EncryptionService.generateMasterKey()

        // Then
        XCTAssertEqual(key.bitCount, 256)
    }

    func testMasterKeyImportExport() throws {
        // Given
        let masterKey = EncryptionService.generateMasterKey()
        let service = EncryptionService(masterKey: masterKey)

        // When
        let exported = service.exportMasterKeyBase64()
        let imported = try EncryptionService.importMasterKeyFromBase64(exported)

        // Then
        XCTAssertEqual(
            masterKey.withUnsafeBytes { Data($0) },
            imported.withUnsafeBytes { Data($0) }
        )
    }

    func testImportInvalidBase64Fails() {
        // When/Then
        XCTAssertThrowsError(
            try EncryptionService.importMasterKeyFromBase64("not-valid-base64")
        )
    }

    func testImportWrongSizeKeyFails() {
        // Given
        let wrongSizeData = Data(repeating: 0, count: 16) // 128 bits instead of 256
        let base64 = wrongSizeData.base64EncodedString()

        // When/Then
        XCTAssertThrowsError(
            try EncryptionService.importMasterKeyFromBase64(base64)
        )
    }

    // MARK: - Keychain Tests

    func testKeychainSaveAndLoad() throws {
        // Given
        let testKey = EncryptionService.generateMasterKey()

        // Clean up any existing key
        try? EncryptionService.deleteMasterKeyFromKeychain()

        // When
        try EncryptionService.saveMasterKeyToKeychain(testKey)
        let loadedKey = try EncryptionService.loadMasterKeyFromKeychain()

        // Then
        XCTAssertEqual(
            testKey.withUnsafeBytes { Data($0) },
            loadedKey.withUnsafeBytes { Data($0) }
        )

        // Cleanup
        try EncryptionService.deleteMasterKeyFromKeychain()
    }

    func testKeychainDelete() throws {
        // Given
        let testKey = EncryptionService.generateMasterKey()
        try EncryptionService.saveMasterKeyToKeychain(testKey)

        // When
        try EncryptionService.deleteMasterKeyFromKeychain()

        // Then
        XCTAssertThrowsError(try EncryptionService.loadMasterKeyFromKeychain())
    }

    // MARK: - Performance Tests

    func testEncryptionPerformance() throws {
        let data = Data(repeating: 0x42, count: 10_000) // 10KB

        measure {
            _ = try? encryptionService.encrypt(data)
        }
    }

    func testDecryptionPerformance() throws {
        let data = Data(repeating: 0x42, count: 10_000) // 10KB
        let encrypted = try encryptionService.encrypt(data)

        measure {
            _ = try? encryptionService.decrypt(ciphertext: encrypted.ciphertext, nonce: encrypted.nonce)
        }
    }
}
