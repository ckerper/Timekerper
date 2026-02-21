import Foundation

/// GitHub Gist sync service. Direct port of sync.js.
/// All methods are static async — no shared mutable state.
enum SyncService {
    private static let gistFilename = "timekerper-sync.json"
    private static let apiBase = "https://api.github.com"

    private static func makeRequest(url: String, method: String = "GET", pat: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// Find existing Timekerper gist by scanning user's gists for the known filename.
    /// Returns (gistId, payload) if found, nil otherwise.
    static func findGist(pat: String) async throws -> (gistId: String, data: SyncPayload)? {
        var page = 1
        while page <= 10 {
            let url = "\(apiBase)/gists?per_page=100&page=\(page)"
            let request = makeRequest(url: url, pat: pat)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw SyncError.networkError }
            if httpResponse.statusCode == 401 { throw SyncError.invalidToken }
            guard httpResponse.statusCode == 200 else { throw SyncError.apiError(httpResponse.statusCode) }

            let gists = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            if gists.isEmpty { break }

            for gist in gists {
                guard let files = gist["files"] as? [String: Any],
                      files[gistFilename] != nil,
                      let gistId = gist["id"] as? String else { continue }

                // Found — fetch full content (list endpoint truncates)
                let fullUrl = "\(apiBase)/gists/\(gistId)"
                let fullRequest = makeRequest(url: fullUrl, pat: pat)
                let (fullData, fullResponse) = try await URLSession.shared.data(for: fullRequest)
                guard let fullHttp = fullResponse as? HTTPURLResponse, fullHttp.statusCode == 200 else {
                    throw SyncError.apiError((fullResponse as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let fullGist = try JSONSerialization.jsonObject(with: fullData) as? [String: Any] ?? [:]
                if let fullFiles = fullGist["files"] as? [String: Any],
                   let fileObj = fullFiles[gistFilename] as? [String: Any],
                   let content = fileObj["content"] as? String,
                   let contentData = content.data(using: .utf8) {
                    do {
                        let payload = try JSONDecoder().decode(SyncPayload.self, from: contentData)
                        return (gistId: gistId, data: payload)
                    } catch let DecodingError.keyNotFound(key, context) {
                        throw SyncError.decodeFailed("Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                    } catch let DecodingError.typeMismatch(type, context) {
                        throw SyncError.decodeFailed("Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                    } catch let DecodingError.valueNotFound(type, context) {
                        throw SyncError.decodeFailed("Null value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                    } catch {
                        throw SyncError.decodeFailed(error.localizedDescription)
                    }
                }
                return nil
            }
            page += 1
        }
        return nil
    }

    /// Create a new private gist with the sync payload. Returns the gist ID.
    static func createGist(pat: String, payload: SyncPayload) async throws -> String {
        let payloadData = try JSONEncoder().encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let body: [String: Any] = [
            "description": "Timekerper sync data",
            "public": false,
            "files": [gistFilename: ["content": payloadString]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let request = makeRequest(url: "\(apiBase)/gists", method: "POST", pat: pat, body: bodyData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw SyncError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let gist = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let gistId = gist["id"] as? String else { throw SyncError.createFailed }
        return gistId
    }

    /// Push local state to an existing gist.
    static func pushToGist(pat: String, gistId: String, payload: SyncPayload) async throws {
        let payloadData = try JSONEncoder().encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let body: [String: Any] = [
            "files": [gistFilename: ["content": payloadString]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let request = makeRequest(url: "\(apiBase)/gists/\(gistId)", method: "PATCH", pat: pat, body: bodyData)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SyncError.networkError }
        if httpResponse.statusCode == 404 { throw SyncError.gistNotFound }
        guard httpResponse.statusCode == 200 else { throw SyncError.apiError(httpResponse.statusCode) }
    }

    /// Pull remote state from a gist.
    static func pullFromGist(pat: String, gistId: String) async throws -> SyncPayload {
        let request = makeRequest(url: "\(apiBase)/gists/\(gistId)", pat: pat)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SyncError.networkError }
        if httpResponse.statusCode == 404 { throw SyncError.gistNotFound }
        guard httpResponse.statusCode == 200 else { throw SyncError.apiError(httpResponse.statusCode) }

        let gist = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let files = gist["files"] as? [String: Any],
              let fileObj = files[gistFilename] as? [String: Any],
              let content = fileObj["content"] as? String,
              let contentData = content.data(using: .utf8) else {
            throw SyncError.fileMissing
        }
        return try JSONDecoder().decode(SyncPayload.self, from: contentData)
    }

    enum SyncError: LocalizedError {
        case invalidToken
        case apiError(Int)
        case networkError
        case gistNotFound
        case createFailed
        case fileMissing
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidToken: return "Invalid token"
            case .apiError(let code): return "GitHub API error: \(code)"
            case .networkError: return "Network error"
            case .gistNotFound: return "Gist not found"
            case .createFailed: return "Failed to create gist"
            case .fileMissing: return "Sync file missing from gist"
            case .decodeFailed(let detail): return "Decode error: \(detail)"
            }
        }
    }
}
