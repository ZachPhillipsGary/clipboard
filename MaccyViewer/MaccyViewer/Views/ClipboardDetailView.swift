import SwiftUI

struct ClipboardDetailView: View {
    let item: ClipboardItem

    @State private var showCopyConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: item.iconName)
                        .font(.title)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading) {
                        Text(item.displayTitle)
                            .font(.headline)
                        Text(item.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Content
                VStack(alignment: .leading, spacing: 12) {
                    Text("Content")
                        .font(.headline)

                    if item.hasImage {
                        // Placeholder for image display
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                            )
                    }

                    Text(item.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.headline)

                    DetailRow(label: "Application", value: item.application ?? "Unknown")
                    DetailRow(label: "First Copied", value: item.formattedFirstCopied)
                    DetailRow(label: "Times Copied", value: "\(item.numberOfCopies)")
                }

                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { copyToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        .alert("Copied", isPresented: $showCopyConfirmation) {
            Button("OK") { }
        } message: {
            Text("Copied to clipboard")
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = item.text
        showCopyConfirmation = true
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        ClipboardDetailView(item: ClipboardItem.sample)
    }
}
