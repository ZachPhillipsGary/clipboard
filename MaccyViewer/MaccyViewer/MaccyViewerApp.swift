import SwiftUI

@main
struct MaccyViewerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Global app state
@MainActor
class AppState: ObservableObject {
    @Published var isConfigured: Bool = false
    @Published var syncService: SyncService?

    init() {
        // Check if sync is already configured
        checkConfiguration()
    }

    private func checkConfiguration() {
        if let _ = UserDefaults.standard.string(forKey: "syncGroupId"),
           let _ = UserDefaults.standard.string(forKey: "syncDeviceId"),
           let _ = UserDefaults.standard.string(forKey: "syncApiEndpoint"),
           let _ = UserDefaults.standard.string(forKey: "syncAuthToken") {
            isConfigured = true
            syncService = SyncService()
        }
    }

    func configure(with config: SyncConfiguration) throws {
        let service = SyncService()
        try service.configure(with: config)
        self.syncService = service
        self.isConfigured = true
    }

    func clearConfiguration() {
        syncService?.clearSyncData()
        syncService = nil
        isConfigured = false
    }
}
