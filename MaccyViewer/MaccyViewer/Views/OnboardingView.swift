import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showScanner = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                // Icon
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                // Title
                Text("Welcome to Maccy Viewer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Description
                Text("Access your Mac's clipboard on your iPhone with end-to-end encryption.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()

                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "End-to-End Encrypted",
                        description: "Your clipboard data is encrypted on your Mac and never readable by the server"
                    )

                    FeatureRow(
                        icon: "icloud.fill",
                        title: "Real-Time Sync",
                        description: "Automatically sync clipboard items across all your devices"
                    )

                    FeatureRow(
                        icon: "magnifyingglass",
                        title: "Search & Browse",
                        description: "Quickly find any clipboard item with powerful search"
                    )
                }
                .padding()

                Spacer()

                // CTA Button
                Button(action: { showScanner = true }) {
                    Label("Scan QR Code to Get Started", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("")
            .sheet(isPresented: $showScanner) {
                QRScannerView { result in
                    handleQRCode(result)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func handleQRCode(_ code: String) {
        do {
            guard let jsonData = code.data(using: .utf8) else {
                throw NSError(domain: "MaccyViewer", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid QR code data"
                ])
            }

            let decoder = JSONDecoder()
            let config = try decoder.decode(SyncConfiguration.self, from: jsonData)

            try appState.configure(with: config)

            showScanner = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
