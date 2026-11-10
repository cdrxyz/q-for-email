import Foundation

public protocol HTTPPosting: Sendable {
    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> HTTPResult
}

public struct HTTPResult: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public enum ChatClientError: Error, Equatable, Sendable {
    case badStatus(Int, String)
    case empty
    case undecodable
}

public struct ChatClient: Sendable {
    public var poster: any HTTPPosting
    public var timeout: TimeInterval

    public init(poster: any HTTPPosting, timeout: TimeInterval = 45) {
        self.poster = poster
        self.timeout = timeout
    }

    public func complete(url: URL, model: String, apiKey: String?, system: String, user: String) async throws -> String {
        let withFormat = try await send(
            url: url,
            model: model,
            apiKey: apiKey,
            system: system,
            user: user,
            jsonMode: true
        )
        if withFormat.status == 400 || withFormat.status == 422 {
            let plain = try await send(
                url: url,
                model: model,
                apiKey: apiKey,
                system: system,
                user: user,
                jsonMode: false
            )
            return try content(from: plain)
        }
        return try content(from: withFormat)
    }

    private func send(
        url: URL,
        model: String,
        apiKey: String?,
        system: String,
        user: String,
        jsonMode: Bool
    ) async throws -> HTTPResult {
        var payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        if jsonMode {
            payload["response_format"] = ["type": "json_object"]
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        var headers = ["Content-Type": "application/json"]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return try await poster.post(url: url, headers: headers, body: body, timeout: timeout)
    }

    private func content(from result: HTTPResult) throws -> String {
        guard (200...299).contains(result.status) else {
            let snippet = String(data: result.body, encoding: .utf8)?.prefix(200) ?? ""
            throw ChatClientError.badStatus(result.status, String(snippet))
        }
        guard let json = try? JSONSerialization.jsonObject(with: result.body) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw ChatClientError.undecodable }
        if let text = message["content"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ChatClientError.empty }
            return trimmed
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ChatClientError.empty }
            return trimmed
        }
        throw ChatClientError.undecodable
    }
}

public struct URLSessionHTTPPoster: HTTPPosting {
    public init() {}

    public func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPResult(status: status, body: data)
    }
}
