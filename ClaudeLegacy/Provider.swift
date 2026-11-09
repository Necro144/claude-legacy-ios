import SwiftUI

// Everything that differs between this app and its sibling lives in this one file.

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let blurb: String
}

struct ChatConfig {
    var key: String
    var model: String
    var system: String
    var temperature: Double
    var maxTokens: Int
}

enum Chunk {
    case text(String)
    case error(String)
    case done
    case skip
}

enum Provider {
    static let name = "Claude"
    static let host = "claude.ai"
    static let webURL = URL(string: "https://claude.ai")!
    static let keyPlaceholder = "sk-ant-..."
    static let keySite = "console.anthropic.com"
    static let apiHost = "api.anthropic.com"
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let supportsTemperature = true
    static let defaultModel = "claude-sonnet-5-5"

    static let models: [ModelInfo] = [
        ModelInfo(id: "claude-fable-5-1", name: "Fable 5.1", blurb: "Most capable"),
        ModelInfo(id: "claude-opus-5-5", name: "Opus 5.5", blurb: "Deep reasoning"),
        ModelInfo(id: "claude-sonnet-5-5", name: "Sonnet 5.5", blurb: "Balanced and fast"),
        ModelInfo(id: "claude-haiku-5-5", name: "Haiku 5.5", blurb: "Quickest, lightest")
    ]

    /// CSS that turns the site's dark greys into true black.
    static let darkCSS = """
    :root, :root[data-mode], .darkmode, [data-theme] {
      --bg-000: 0 0% 0% !important; --bg-100: 0 0% 0% !important; --bg-200: 0 0% 0% !important;
      --bg-300: 0 0% 4% !important; --bg-400: 0 0% 6% !important; --bg-500: 0 0% 8% !important;
    }
    html, body { background: #000 !important; }
    """

    static func request(_ c: ChatConfig, history: [[String: String]]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(c.key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "model": c.model,
            "max_tokens": c.maxTokens,
            "temperature": c.temperature,
            "stream": true,
            "messages": history
        ]
        if !c.system.isEmpty { body["system"] = c.system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func chunk(from payload: String) -> Chunk {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return .skip }
        switch type {
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any], let piece = delta["text"] as? String { return .text(piece) }
            return .skip
        case "message_stop":
            return .done
        case "error":
            if let err = obj["error"] as? [String: Any], let m = err["message"] as? String { return .error(m) }
            return .error(payload)
        default:
            return .skip
        }
    }

    static func apiMessage(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let message = err["message"] as? String { return message }
        return raw
    }
}
