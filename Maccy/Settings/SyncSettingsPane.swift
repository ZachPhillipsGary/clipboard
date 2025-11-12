import SwiftUI
import Defaults
import Settings

@available(macOS 14.0, *)
struct SyncSettingsPane: View {
    @StateObject private var syncService: SyncService

    @Default(.syncEnabled) private var syncEnabled
    @Default(.syncInterval) private var syncInterval
    @Default(.lastSyncDate) private var lastSyncDate

    @State private var showQRCode = false
    @State private var qrCodeImage: NSImage?
    @State private var syncConfig: SyncConfiguration?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var syncStatus: SyncStatusResponse?
    @State private var isLoadingStatus = false

    // Default API endpoint (can be changed by user)
    @State private var apiEndpoint = "https://maccy-sync-backend.your-subdomain.workers.dev"

    init(syncService: SyncService) {
        _syncService = StateObject(wrappedValue: syncService)
    }

    var body: some View {
        Settings.Container(contentWidth: 500) {
            // Status Section
            Settings.Section(
                bottomDivider: true,
                label: { Text("Sync Status") }
            ) {
                if syncService.isConfigured {
                    HStack {
                        Image(systemName: syncEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(syncEnabled ? .green : .gray)
                        Text(syncEnabled ? "Sync Enabled" : "Sync Disabled")
                        Spacer()
                    }

                    if let lastSync = lastSyncDate {
                        HStack {
                            Text("Last Sync:")
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }

                    // Sync status indicator
                    switch syncService.status {
                    case .idle:
                        EmptyView()
                    case .syncing:
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Syncing...")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    case .success(let itemsSynced):
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("Synced \(itemsSynced) items")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    case .error(let error):
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                } else {
                    Text("Sync not configured")
                        .foregroundColor(.secondary)
                }
            }

            // Configuration Section
            Settings.Section(
                bottomDivider: true,
                label: { Text("Configuration") }
            ) {
                if !syncService.isConfigured {
                    // Setup flow
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set up end-to-end encrypted sync to access your clipboard on other devices.")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("API Endpoint", text: $apiEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .help("Cloudflare Worker URL")

                        Button(action: generateQRCode) {
                            Label("Generate QR Code", systemImage: "qrcode")
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Scan this QR code with the Maccy Viewer app on your iPhone or iPad.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // Already configured
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $syncEnabled) {
                            Text("Enable Sync")
                        }
                        .onChange(of: syncEnabled) { _, newValue in
                            if newValue {
                                syncService.enableSync()
                            } else {
                                syncService.disableSync()
                            }
                        }

                        HStack {
                            Text("Sync Interval:")
                            Picker("", selection: $syncInterval) {
                                Text("15 seconds").tag(15)
                                Text("30 seconds").tag(30)
                                Text("1 minute").tag(60)
                                Text("5 minutes").tag(300)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        Button(action: manualSync) {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!syncEnabled || !syncService.status.isIdle)

                        Button(action: { showQRCode = true }) {
                            Label("Show QR Code", systemImage: "qrcode")
                        }
                    }
                }
            }

            // Devices Section
            if syncService.isConfigured {
                Settings.Section(
                    bottomDivider: true,
                    label: { Text("Devices") }
                ) {
                    if let status = syncStatus {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(status.device_count) device(s) connected")
                                .foregroundColor(.secondary)

                            ForEach(status.devices, id: \.id) { device in
                                HStack {
                                    Image(systemName: deviceIcon(device.type))
                                    VStack(alignment: .leading) {
                                        Text(device.name)
                                        Text("Last seen: \(Date(timeIntervalSince1970: Double(device.last_seen) / 1000), style: .relative)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if device.is_active {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else if isLoadingStatus {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(action: loadSyncStatus) {
                            Label("Load Devices", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }

            // Advanced Section
            if syncService.isConfigured {
                Settings.Section(title: "") {
                    Button(action: clearSync) {
                        Text("Clear Sync Data")
                            .foregroundColor(.red)
                    }
                    .help("Remove all sync configuration and disable sync")
                }
            }
        }
        .sheet(isPresented: $showQRCode) {
            QRCodeSheet(image: qrCodeImage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if syncService.isConfigured {
                loadSyncStatus()
            }
        }
    }

    // MARK: - Actions

    private func generateQRCode() {
        do {
            let (config, image) = try QRCodeGenerator.createPrimarySyncConfiguration(
                apiEndpoint: apiEndpoint
            )

            self.syncConfig = config
            self.qrCodeImage = image

            // Configure sync service
            try syncService.configure(with: config)

            // Show QR code
            showQRCode = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func manualSync() {
        Task {
            do {
                try await syncService.performSync()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func loadSyncStatus() {
        guard syncService.isConfigured else { return }

        isLoadingStatus = true

        Task {
            do {
                let status = try await syncService.getStatus()
                await MainActor.run {
                    self.syncStatus = status
                    self.isLoadingStatus = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingStatus = false
                    errorMessage = "Failed to load sync status: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func clearSync() {
        do {
            try syncService.clearSyncData()
            syncStatus = nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deviceIcon(_ type: String) -> String {
        switch type {
        case "macos":
            return "desktopcomputer"
        case "ios":
            return "iphone"
        case "android":
            return "smartphone"
        case "windows":
            return "pc"
        case "linux":
            return "server.rack"
        default:
            return "questionmark.circle"
        }
    }
}

// MARK: - QR Code Sheet

struct QRCodeSheet: View {
    let image: NSImage?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Scan QR Code")
                .font(.title)

            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 400, height: 400)
                    .background(Color.white)
                    .border(Color.gray, width: 1)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 400, height: 400)
                    .overlay(Text("QR Code unavailable"))
            }

            Text("Open the Maccy Viewer app on your iPhone or iPad and scan this code to pair your device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 500, height: 600)
    }
}

#Preview {
    @Previewable @StateObject var syncService = SyncService(
        modelContext: Storage.shared.modelContext,
        storage: Storage.shared
    )

    SyncSettingsPane(syncService: syncService)
        .environment(\.locale, .init(identifier: "en"))
}
