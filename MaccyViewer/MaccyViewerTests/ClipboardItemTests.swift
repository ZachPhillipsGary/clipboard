import XCTest
@testable import MaccyViewer

final class ClipboardItemTests: XCTestCase {
    // MARK: - Initialization Tests

    func testClipboardItemInitialization() {
        // Given
        let id = UUID().uuidString
        let text = "Test clipboard text"
        let application = "Safari"
        let now = Date()

        // When
        let item = ClipboardItem(
            id: id,
            text: text,
            application: application,
            firstCopiedAt: now,
            lastCopiedAt: now,
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // Then
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.text, text)
        XCTAssertEqual(item.application, application)
        XCTAssertEqual(item.numberOfCopies, 1)
        XCTAssertFalse(item.hasImage)
        XCTAssertNil(item.imageData)
    }

    // MARK: - Display Title Tests

    func testDisplayTitleSingleLine() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Single line text",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let title = item.displayTitle

        // Then
        XCTAssertEqual(title, "Single line text")
    }

    func testDisplayTitleMultiLine() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "First line\nSecond line\nThird line",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let title = item.displayTitle

        // Then
        XCTAssertEqual(title, "First line")
    }

    func testDisplayTitleEmptyText() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let title = item.displayTitle

        // Then
        XCTAssertEqual(title, "Empty")
    }

    // MARK: - Preview Tests

    func testPreviewSingleLine() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Single line",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let preview = item.preview

        // Then
        XCTAssertEqual(preview, "")
    }

    func testPreviewMultiLine() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "First line\nSecond line\nThird line",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let preview = item.preview

        // Then
        XCTAssertEqual(preview, "Second line Third line")
    }

    // MARK: - Pin Tests

    func testIsPinnedTrue() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Pinned item",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: "a",
            hasImage: false,
            imageData: nil
        )

        // When
        let isPinned = item.isPinned

        // Then
        XCTAssertTrue(isPinned)
    }

    func testIsPinnedFalse() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Unpinned item",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let isPinned = item.isPinned

        // Then
        XCTAssertFalse(isPinned)
    }

    // MARK: - Icon Name Tests

    func testIconNameForImage() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Image",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: true,
            imageData: Data()
        )

        // When
        let icon = item.iconName

        // Then
        XCTAssertEqual(icon, "photo")
    }

    func testIconNameForURL() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "https://example.com",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let icon = item.iconName

        // Then
        XCTAssertEqual(icon, "link")
    }

    func testIconNameForShortText() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Short",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let icon = item.iconName

        // Then
        XCTAssertEqual(icon, "textformat")
    }

    func testIconNameForLongText() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: String(repeating: "A", count: 100),
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let icon = item.iconName

        // Then
        XCTAssertEqual(icon, "doc.text")
    }

    func testIconNameForMultilineText() {
        // Given
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Line 1\nLine 2",
            application: nil,
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let icon = item.iconName

        // Then
        XCTAssertEqual(icon, "doc.text")
    }

    // MARK: - Date Formatting Tests

    func testFormattedDate() {
        // Given
        let now = Date()
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Test",
            application: nil,
            firstCopiedAt: now,
            lastCopiedAt: now,
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let formatted = item.formattedDate

        // Then
        XCTAssertFalse(formatted.isEmpty)
        // Should contain relative time like "now" or "just now"
    }

    func testFormattedFirstCopied() {
        // Given
        let now = Date()
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: "Test",
            application: nil,
            firstCopiedAt: now,
            lastCopiedAt: now,
            numberOfCopies: 1,
            pin: nil,
            hasImage: false,
            imageData: nil
        )

        // When
        let formatted = item.formattedFirstCopied

        // Then
        XCTAssertFalse(formatted.isEmpty)
        // Should contain formatted date and time
    }

    // MARK: - Codable Tests

    func testClipboardItemCodable() throws {
        // Given
        let original = ClipboardItem(
            id: UUID().uuidString,
            text: "Test text",
            application: "Safari",
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 3,
            pin: "a",
            hasImage: false,
            imageData: nil
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClipboardItem.self, from: data)

        // Then
        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.text, decoded.text)
        XCTAssertEqual(original.application, decoded.application)
        XCTAssertEqual(original.numberOfCopies, decoded.numberOfCopies)
        XCTAssertEqual(original.pin, decoded.pin)
        XCTAssertEqual(original.hasImage, decoded.hasImage)
    }

    func testClipboardItemWithImageDataCodable() throws {
        // Given
        let imageData = Data(repeating: 0x42, count: 100)
        let original = ClipboardItem(
            id: UUID().uuidString,
            text: "Image item",
            application: "Photos",
            firstCopiedAt: Date(),
            lastCopiedAt: Date(),
            numberOfCopies: 1,
            pin: nil,
            hasImage: true,
            imageData: imageData
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClipboardItem.self, from: data)

        // Then
        XCTAssertEqual(original.hasImage, decoded.hasImage)
        XCTAssertEqual(original.imageData, decoded.imageData)
    }

    // MARK: - Sample Data Tests

    func testSampleClipboardItem() {
        // When
        let sample = ClipboardItem.sample

        // Then
        XCTAssertFalse(sample.id.isEmpty)
        XCTAssertFalse(sample.text.isEmpty)
        XCTAssertNotNil(sample.application)
    }

    func testSamplesClipboardItems() {
        // When
        let samples = ClipboardItem.samples

        // Then
        XCTAssertGreaterThan(samples.count, 0)
        XCTAssertTrue(samples.allSatisfy { !$0.id.isEmpty })
    }
}
