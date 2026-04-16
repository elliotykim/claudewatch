import Foundation

/// Polls the Claude Code component from Anthropic's public status page.
struct StatusClient {

    let session: URLSession
    let endpoint: URL
    let componentID: String

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://status.claude.com/api/v2/components.json")!,
        componentID: String = StatusComponent.claudeCodeID
    ) {
        self.session = session
        self.endpoint = endpoint
        self.componentID = componentID
    }

    enum FetchError: Error, LocalizedError {
        case http(Int)
        case transport(Error)
        case malformed
        var errorDescription: String? {
            switch self {
            case .http(let c): return "HTTP \(c)"
            case .transport(let e): return e.localizedDescription
            case .malformed: return "Claude Code component not found"
            }
        }
    }

    func fetch() async -> Result<StatusState, FetchError> {
        var req = URLRequest(url: endpoint)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("ClaudeWatch/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .failure(.http(0)) }
            guard http.statusCode == 200 else { return .failure(.http(http.statusCode)) }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let components = json["components"] as? [[String: Any]]
            else { return .failure(.malformed) }

            guard let component = components.first(where: { ($0["id"] as? String) == componentID }),
                  let statusStr = component["status"] as? String
            else { return .failure(.malformed) }

            let severity = Severity(componentStatus: statusStr)
            let state = StatusState(
                severity: severity,
                description: severity.label,
                lastCheckedAt: Date(),
                lastError: nil
            )
            return .success(state)
        } catch {
            return .failure(.transport(error))
        }
    }
}
