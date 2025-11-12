import Foundation

/// HTTP client for communicating with Maccy sync backend
/// iOS version - reuses same API as macOS
final class SyncAPIClient {
    enum APIError: LocalizedError {
        case invalidURL
        case noResponse
        case invalidResponse(Int, String?)
        case networkError(Error)
        case decodingError(Error)
        case unauthorized
        case rateLimited(resetAt: Int64)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noResponse:
                return "No response from server"
            case .invalidResponse(let status, let message):
                return "Server error (\(status)): \(message ?? "Unknown error")"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .unauthorized:
                return "Unauthorized. Please re-pair your device."
            case .rateLimited(let resetAt):
                let date = Date(timeIntervalSince1970: Double(resetAt) / 1000)
                return "Rate limited. Try again at \(date)"
            }
        }
    }

    private let baseURL: String
    private let authToken: String?
    private let session: URLSession

    init(baseURL: String, authToken: String? = nil) {
        self.baseURL = baseURL.trimmingSuffix("/")
        self.authToken = authToken

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func registerDevice(
        syncGroupId: String,
        deviceId: String,
        deviceName: String,
        deviceType: String
    ) async throws -> RegisterDeviceResponse {
        let url = try buildURL(path: "/api/sync/register")
        let request = RegisterDeviceRequest(
            sync_group_id: syncGroupId,
            device_id: deviceId,
            device_name: deviceName,
            device_type: deviceType
        )

        return try await post(url: url, body: request, authenticated: false)
    }

    func pullItems(since: Int64? = nil, limit: Int = 100) async throws -> PullItemsResponse {
        var components = URLComponents(string: baseURL + "/api/sync/pull")!

        var queryItems: [URLQueryItem] = []
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: String(since)))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        return try await get(url: url, authenticated: true)
    }

    func getStatus() async throws -> SyncStatusResponse {
        let url = try buildURL(path: "/api/sync/status")
        return try await get(url: url, authenticated: true)
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(url: URL, authenticated: Bool) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated {
            guard let token = authToken else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await performRequest(request)
    }

    private func post<T: Encodable, R: Decodable>(
        url: URL,
        body: T,
        authenticated: Bool
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated {
            guard let token = authToken else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        return try await performRequest(request)
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            if let resetString = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let resetAt = Int64(resetString) {
                throw APIError.rateLimited(resetAt: resetAt)
            }
            throw APIError.rateLimited(resetAt: 0)
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage: String?
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorMessage = errorResponse.error
            } else {
                errorMessage = String(data: data, encoding: .utf8)
            }

            throw APIError.invalidResponse(httpResponse.statusCode, errorMessage)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }

    private func buildURL(path: String) throws -> URL {
        let urlString = baseURL + path
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        return url
    }
}

// API Models
struct RegisterDeviceRequest: Codable {
    let sync_group_id: String
    let device_id: String
    let device_name: String
    let device_type: String
}

struct RegisterDeviceResponse: Codable {
    let token: String
    let sync_group: SyncGroup
    let device: Device
}

struct SyncGroup: Codable {
    let id: String
    let created_at: Int64
    let last_activity: Int64
}

struct Device: Codable {
    let id: String
    let sync_group_id: String
    let device_name: String
    let device_type: String
    let registered_at: Int64
    let last_seen: Int64
    let is_active: Int
}

struct PullItemsResponse: Codable {
    let items: [RemoteEncryptedItem]
    let has_more: Bool
    let server_timestamp: Int64
}

struct RemoteEncryptedItem: Codable {
    let id: String
    let device_id: String
    let encrypted_payload: String
    let nonce: String
    let created_at: Int64
    let updated_at: Int64
    let is_deleted: Bool
    let item_hash: String
    let compressed: Bool
    let size_bytes: Int
}

struct SyncStatusResponse: Codable {
    let sync_group_id: String
    let device_count: Int
    let item_count: Int
    let total_size_bytes: Int64
    let last_activity: Int64
    let devices: [DeviceInfo]
}

struct DeviceInfo: Codable {
    let id: String
    let name: String
    let type: String
    let last_seen: Int64
    let is_active: Bool
}

struct ErrorResponse: Codable {
    let error: String
    let code: String
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }
        return self
    }
}
