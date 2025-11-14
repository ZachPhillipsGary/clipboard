import AppKit
import CoreImage
import Foundation

/// QR code generator for device pairing
@available(macOS 14.0, *)
struct QRCodeGenerator {
    // MARK: - Types

    enum QRError: LocalizedError {
        case generationFailed
        case invalidConfiguration

        var errorDescription: String? {
            switch self {
            case .generationFailed:
                return "Failed to generate QR code"
            case .invalidConfiguration:
                return "Invalid sync configuration"
            }
        }
    }

    // MARK: - QR Code Generation

    /// Generate QR code image from sync configuration
    static func generateQRCode(
        syncGroupId: String,
        masterKey: String,
        apiEndpoint: String,
        deviceId: String,
        size: CGSize = CGSize(width: 512, height: 512)
    ) throws -> NSImage {
        // Create sync configuration
        let config = SyncConfiguration(
            version: 1,
            syncGroupId: syncGroupId,
            masterKey: masterKey,
            apiEndpoint: apiEndpoint,
            deviceId: deviceId
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(config)

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw QRError.generationFailed
        }

        // Generate QR code
        return try generateQRCode(from: jsonString, size: size)
    }

    /// Generate QR code image from string
    static func generateQRCode(from string: String, size: CGSize) throws -> NSImage {
        guard let data = string.data(using: .utf8) else {
            throw QRError.generationFailed
        }

        // Create QR code filter
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw QRError.generationFailed
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction

        // Get output image
        guard let outputImage = filter.outputImage else {
            throw QRError.generationFailed
        }

        // Scale to desired size
        let scaleX = size.width / outputImage.extent.width
        let scaleY = size.height / outputImage.extent.height
        let scale = min(scaleX, scaleY)

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Render to NSImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw QRError.generationFailed
        }

        let nsImage = NSImage(cgImage: cgImage, size: size)
        return nsImage
    }

    /// Create new sync configuration for primary device
    static func createPrimarySyncConfiguration(apiEndpoint: String) throws -> (config: SyncConfiguration, image: NSImage) {
        // Generate IDs and key
        let syncGroupId = UUID().uuidString
        let deviceId = UUID().uuidString
        let masterKey = EncryptionService.generateMasterKey()
        let masterKeyBase64 = masterKey.withUnsafeBytes { Data($0).base64EncodedString() }

        // Save master key to keychain
        try EncryptionService.saveMasterKeyToKeychain(masterKey)

        // Create configuration
        let config = SyncConfiguration(
            version: 1,
            syncGroupId: syncGroupId,
            masterKey: masterKeyBase64,
            apiEndpoint: apiEndpoint,
            deviceId: deviceId
        )

        // Generate QR code
        let qrImage = try generateQRCode(
            syncGroupId: syncGroupId,
            masterKey: masterKeyBase64,
            apiEndpoint: apiEndpoint,
            deviceId: deviceId,
            size: CGSize(width: 512, height: 512)
        )

        return (config, qrImage)
    }
}
