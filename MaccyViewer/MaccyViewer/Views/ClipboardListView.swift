import SwiftUI

struct ClipboardListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ClipboardListViewModel()

    @State private var searchText = ""
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading clipboard...")
                } else if viewModel.items.isEmpty {
                    emptyState
                } else {
                    clipboardList
                }
            }
            .navigationTitle("Clipboard")
            .searchable(text: $searchText, prompt: "Search clipboard")
            .onChange(of: searchText) { _, newValue in
                viewModel.search(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                if let syncService = appState.syncService {
                    viewModel.syncService = syncService
                    Task {
                        await viewModel.loadItems()
                    }
                }
            }
        }
    }

    private var clipboardList: some View {
        List {
            ForEach(viewModel.filteredItems) { item in
                NavigationLink(destination: ClipboardDetailView(item: item)) {
                    ClipboardItemRow(item: item)
                }
                .swipeActions(edge: .trailing) {
                    Button(action: { copyToClipboard(item) }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Clipboard Items")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Copy something on your Mac to see it here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        UIPasteboard.general.string = item.text
        // Show toast notification (could be improved with a custom toast)
        viewModel.showCopyConfirmation()
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Icon based on content type
                Image(systemName: item.iconName)
                    .foregroundColor(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(item.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Pin indicator
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }

            if !item.preview.isEmpty {
                Text(item.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class ClipboardListViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var filteredItems: [ClipboardItem] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var showError = false
    @Published var errorMessage: String?

    var syncService: SyncService?

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        guard let syncService = syncService else {
            errorMessage = "Sync service not configured"
            showError = true
            return
        }

        do {
            // Pull items from server
            try await syncService.performSync()

            // Get decrypted items (placeholder - needs implementation)
            // In production, this would decrypt and cache items locally
            items = []
            filteredItems = items
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await loadItems()
    }

    func search(query: String) {
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.text.localizedCaseInsensitiveContains(query) ||
                item.displayTitle.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func showCopyConfirmation() {
        // Could implement a toast notification here
        print("Copied to clipboard")
    }
}

#Preview {
    ClipboardListView()
        .environmentObject(AppState())
}
