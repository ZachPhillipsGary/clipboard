import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var syncInterval = 30
    @State private var showDisconnectAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section("Sync") {
                    if let syncService = appState.syncService {
                        HStack {
                            Text("Status")
                            Spacer()
                            if syncService.isEnabled {
                                Label("Enabled", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("Disabled", systemImage: "circle")
                                    .foregroundColor(.gray)
                            }
                        }

                        if let lastSync = syncService.lastSyncTime {
                            HStack {
                                Text("Last Sync")
                                Spacer()
                                Text(lastSync, style: .relative)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Picker("Sync Interval", selection: $syncInterval) {
                            Text("15 seconds").tag(15)
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("5 minutes").tag(300)
                        }

                        Button(action: { manualSync() }) {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }

                Section("Device") {
                    HStack {
                        Text("Device Name")
                        Spacer()
                        Text(UIDevice.current.name)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Device Type")
                        Spacer()
                        Text("iOS")
                            .foregroundColor(.secondary)
                    }
                }

                Section("About") {
                    Link("Maccy on GitHub", destination: URL(string: "https://github.com/p0deje/Maccy")!)

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: { showDisconnectAlert = true }) {
                        Text("Disconnect & Clear Data")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Disconnect Device?", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    disconnect()
                }
            } message: {
                Text("This will remove all sync data from this device. You'll need to scan the QR code again to reconnect.")
            }
        }
    }

    private func manualSync() {
        guard let syncService = appState.syncService else { return }

        Task {
            try? await syncService.performSync()
        }
    }

    private func disconnect() {
        appState.clearConfiguration()
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
