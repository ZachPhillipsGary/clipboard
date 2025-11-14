import Foundation
import OSLog

/// HTTP client for communicating with Maccy sync backend
@available(macOS 14.0, *)
final class SyncAPIClient {
    // MARK: - Types

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

    // MARK: - Properties

    private let baseURL: String
    private let authToken: String?
    private let session: URLSession
    private let logger = Logger(subsystem: "org.p0deje.Maccy", category: "SyncAPIClient")

    // MARK: - Initialization

    init(baseURL: String, authToken: String? = nil) {
        self.baseURL = baseURL.trimmingSuffix("/")
        self.authToken = authToken

        // Configure URLSession with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - API Methods

    /// Health check
    func healthCheck() async throws -> Bool {
        let url = try buildURL(path: "/health")
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noResponse
        }

        return httpResponse.statusCode == 200
    }

    /// Register device and get auth token
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

    /// Push encrypted items to server
    func pushItems(_ items: [EncryptedItemPayload]) async throws -> PushItemsResponse {
        let url = try buildURL(path: "/api/sync/push")
        let request = PushItemsRequest(items: items)

        logger.info("Pushing \(items.count) items")
        return try await post(url: url, body: request, authenticated: true)
    }

    /// Pull encrypted items from server
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

        logger.info("Pulling items since \(since ?? 0)")
        return try await get(url: url, authenticated: true)
    }

    /// Delete items on server
    func deleteItems(_ itemIds: [String]) async throws -> DeleteItemsResponse {
        let url = try buildURL(path: "/api/sync/delete")
        let request = DeleteItemsRequest(item_ids: itemIds)

        logger.info("Deleting \(itemIds.count) items")
        return try await post(url: url, body: request, authenticated: true)
    }

    /// Get sync status
    func getStatus() async throws -> SyncStatusResponse {
        let url = try buildURL(path: "/api/sync/status")

        logger.info("Fetching sync status")
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

        // Encode body
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        return try await performRequest(request)
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Network request failed: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noResponse
        }

        logger.debug("Response status: \(httpResponse.statusCode)")

        // Check for errors
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            // Parse rate limit reset time
            if let resetString = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let resetAt = Int64(resetString) {
                throw APIError.rateLimited(resetAt: resetAt)
            }
            throw APIError.rateLimited(resetAt: 0)
        }

        if httpResponse.statusCode >= 400 {
            // Try to parse error response
            let errorMessage: String?
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorMessage = errorResponse.error
            } else {
                errorMessage = String(data: data, encoding: .utf8)
            }

            throw APIError.invalidResponse(httpResponse.statusCode, errorMessage)
        }

        // Decode success response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
            logger.debug("Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Helpers

    private func buildURL(path: String) throws -> URL {
        let urlString = baseURL + path
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        return url
    }
}

// MARK: - String Extension

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }
        return self
    }
}
