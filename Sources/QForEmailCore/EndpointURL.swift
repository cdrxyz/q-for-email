import Foundation

public enum EndpointURLError: Error, Equatable, Sendable {
    case empty
    case invalid
    case unsupportedScheme
    case userinfo
    case missingHost
}

public enum EndpointURL {
    public static func chatCompletionsURL(from raw: String) -> Result<URL, EndpointURLError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased()
        else { return .failure(.invalid) }
        guard scheme == "http" || scheme == "https" else { return .failure(.unsupportedScheme) }
        if components.user != nil || components.password != nil { return .failure(.userinfo) }
        guard let host = components.host, !host.isEmpty else { return .failure(.missingHost) }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty || path == "/" {
            path = "/v1/chat/completions"
        } else if path.hasSuffix("/chat/completions") {
            // already complete
        } else if path.hasSuffix("/v1") {
            path += "/chat/completions"
        } else {
            path += "/v1/chat/completions"
        }

        var out = components
        out.scheme = scheme
        out.path = path
        out.query = nil
        out.fragment = nil
        guard let url = out.url else { return .failure(.invalid) }
        return .success(url)
    }

    /// True only for this machine. A LAN address still gets the remote confirmation.
    public static func isLoopback(_ url: URL) -> Bool {
        let host = (url.host ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
