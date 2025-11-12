import Foundation
import SwiftUI

struct ClipboardItem: Identifiable, Codable {
    let id: String
    let text: String
    let application: String?
    let firstCopiedAt: Date
    let lastCopiedAt: Date
    let numberOfCopies: Int
    let pin: String?
    let hasImage: Bool
    let imageData: Data?

    var displayTitle: String {
        let lines = text.components(separatedBy: .newlines)
        return lines.first ?? "Empty"
    }

    var preview: String {
        let lines = text.components(separatedBy: .newlines)
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ")
        }
        return ""
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastCopiedAt, relativeTo: Date())
    }

    var formattedFirstCopied: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: firstCopiedAt)
    }

    var isPinned: Bool {
        return pin != nil
    }

    var iconName: String {
        if hasImage {
            return "photo"
        } else if text.contains("http://") || text.contains("https://") {
            return "link"
        } else if text.count < 50 && !text.contains("\n") {
            return "textformat"
        } else {
            return "doc.text"
        }
    }

    // Sample data for previews
    static var sample: ClipboardItem {
        ClipboardItem(
            id: UUID().uuidString,
            text: "Sample clipboard text\nThis is a multi-line example of clipboard content that could be copied from your Mac.",
            application: "Safari",
            firstCopiedAt: Date().addingTimeInterval(-3600),
            lastCopiedAt: Date().addingTimeInterval(-300),
            numberOfCopies: 3,
            pin: nil,
            hasImage: false,
            imageData: nil
        )
    }

    static var samples: [ClipboardItem] {
        [
            ClipboardItem(
                id: UUID().uuidString,
                text: "https://github.com/p0deje/Maccy",
                application: "Safari",
                firstCopiedAt: Date().addingTimeInterval(-7200),
                lastCopiedAt: Date().addingTimeInterval(-600),
                numberOfCopies: 1,
                pin: nil,
                hasImage: false,
                imageData: nil
            ),
            ClipboardItem(
                id: UUID().uuidString,
                text: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello, World!\")\n    }\n}",
                application: "Xcode",
                firstCopiedAt: Date().addingTimeInterval(-3600),
                lastCopiedAt: Date().addingTimeInterval(-1800),
                numberOfCopies: 5,
                pin: "a",
                hasImage: false,
                imageData: nil
            ),
            ClipboardItem(
                id: UUID().uuidString,
                text: "Meeting notes from today",
                application: "Notes",
                firstCopiedAt: Date().addingTimeInterval(-300),
                lastCopiedAt: Date().addingTimeInterval(-60),
                numberOfCopies: 2,
                pin: nil,
                hasImage: false,
                imageData: nil
            )
        ]
    }
}

// Extension to convert from SerializableHistoryItem
extension ClipboardItem {
    init(from serializable: SerializableHistoryItem) {
        self.id = serializable.syncId
        self.text = serializable.title
        self.application = serializable.application
        self.firstCopiedAt = serializable.firstCopiedAt
        self.lastCopiedAt = serializable.lastCopiedAt
        self.numberOfCopies = serializable.numberOfCopies
        self.pin = serializable.pin

        // Check for image content
        let imageTypes = ["public.png", "public.jpeg", "public.tiff", "public.heic"]
        let hasImageContent = serializable.contents.contains { content in
            imageTypes.contains(where: { content.type.contains($0) })
        }
        self.hasImage = hasImageContent

        // Extract image data if available
        if hasImageContent,
           let imageContent = serializable.contents.first(where: { content in
               imageTypes.contains(where: { content.type.contains($0) })
           }) {
            self.imageData = imageContent.value
        } else {
            self.imageData = nil
        }
    }
}
