import Foundation
import Security

enum APIError: LocalizedError {
    case configuration, unauthorized, invalidResponse, server(String), keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .configuration: "Birthday GO needs a valid BG_API_BASE_URL build setting."
        case .unauthorized: "This invitation or device is no longer authorized."
        case .invalidResponse: "The server returned an unreadable response."
        case .server(let code):
            switch code {
            case "game_unavailable": "No published adventure is ready yet."
            case "location_required": "Turn on location, or enter the fallback code on this pin."
            case "location_inaccurate": "GPS is fuzzy here. Wait a few seconds, or enter the fallback code."
            case "dwell_required": "Stay at the pin a moment longer, then catch again."
            case "outside_radius": "Move closer to the pin, or enter the fallback code."
            case "request_failed": "The catch could not be saved. Check the network and try again."
            default: code.replacingOccurrences(of: "_", with: " ").capitalized
            }
        case .keychain: "Secure credential storage is unavailable."
        }
    }
}

actor APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) throws {
        let raw = Bundle.main.object(forInfoDictionaryKey: "BG_API_BASE_URL") as? String
        let value = (raw?.isEmpty == false && raw?.contains("$(") == false && raw?.contains("YOUR-PROJECT") == false)
            ? raw!
            : "https://ookqnalokcpqvdojmcmy.supabase.co/functions/v1/"
        guard let url = URL(string: value) else { throw APIError.configuration }
        self.baseURL = url
        self.session = session
        self.decoder = JSONDecoder.supabase
        self.encoder = JSONEncoder.supabase
    }

    func joinOpenGame(deviceName: String, installationId: UUID) async throws -> RedeemResponse {
        let body = JoinRequest(deviceName: deviceName, installationId: installationId)
        let data = try await request(path: "player-join", body: body, authenticated: false)
        return try decoder.decode(RedeemResponse.self, from: data)
    }

    func redeem(invitationToken: String, deviceName: String, installationId: UUID) async throws -> RedeemResponse {
        let body = RedeemRequest(invitationToken: invitationToken, deviceName: deviceName, installationId: installationId)
        let data = try await request(path: "player-redeem", body: body, authenticated: false)
        return try decoder.decode(RedeemResponse.self, from: data)
    }

    func recover(recoveryToken: String, deviceName: String, installationId: UUID) async throws -> RedeemResponse {
        let body = RecoveryRequest(recoveryToken: recoveryToken, deviceName: deviceName, installationId: installationId)
        let data = try await request(path: "player-recover", body: body, authenticated: false)
        return try decoder.decode(RedeemResponse.self, from: data)
    }

    func sync(installationId: UUID, avatarStyle: [String: String]? = nil, resetCollection: Bool = false) async throws -> PlayerSnapshot {
        let data = try await request(
            path: "player-sync",
            body: SyncRequest(avatarStyle: avatarStyle, resetCollection: resetCollection ? true : nil),
            installationId: installationId
        )
        return try decoder.decode(PlayerSnapshot.self, from: data)
    }

    func progress(_ progress: PendingProgress, installationId: UUID) async throws -> PlayerSnapshot {
        let data = try await request(path: "player-progress", body: progress, installationId: installationId)
        return try decoder.decode(PlayerSnapshot.self, from: data)
    }

    private func request<T: Encodable>(
        path: String,
        body: T,
        authenticated: Bool = true,
        installationId: UUID? = nil
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)
        let bundled = Bundle.main.object(forInfoDictionaryKey: "BG_SUPABASE_ANON_KEY") as? String
        let anon = (bundled?.isEmpty == false && bundled?.contains("$(") == false)
            ? bundled!
            : "sb_publishable_DEnBR0L7_tN5veEl9nMGNA_5zsIZVI6"
        request.setValue(anon, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anon)", forHTTPHeaderField: "authorization")
        if authenticated {
            guard let token = try KeychainStore.read("playerAccessToken"), let installationId else {
                throw APIError.unauthorized
            }
            request.setValue(token, forHTTPHeaderField: "x-player-token")
            request.setValue(installationId.uuidString, forHTTPHeaderField: "x-installation-id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? decoder.decode(ServerError.self, from: data).error) ?? "request_failed"
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server(code)
        }
        return data
    }
}

struct JoinRequest: Encodable { let deviceName: String; let installationId: UUID }
struct RedeemRequest: Encodable { let invitationToken: String; let deviceName: String; let installationId: UUID }
struct RecoveryRequest: Encodable { let recoveryToken: String; let deviceName: String; let installationId: UUID }
struct SyncRequest: Encodable {
    var avatarStyle: [String: String]?
    var resetCollection: Bool?
}
struct RedeemResponse: Decodable { let playerId: UUID; let gameId: UUID; let recipientName: String; let accessToken: String }
struct ServerError: Decodable { let error: String }

enum KeychainStore {
    private static let service = "com.example.BirthdayGO"

    static func save(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIError.keychain(status) }
    }

    static func read(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APIError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return decoder
    }
}

extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
