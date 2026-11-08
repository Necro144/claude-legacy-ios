import SwiftUI

enum Theme {
    static let bg = Color.black
    static let surface = Color(red: 0.07, green: 0.07, blue: 0.075)
    static let surface2 = Color(red: 0.125, green: 0.125, blue: 0.135)
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let hairline = Color.white.opacity(0.09)
    static let dim = Color.white.opacity(0.55)
}

struct ClaudeModel: Identifiable {
    let id: String
    let name: String
    let blurb: String
}

enum ClaudeModels {
    static let all: [ClaudeModel] = [
        ClaudeModel(id: "claude-fable-5-1", name: "Fable 5.1", blurb: "Most capable"),
        ClaudeModel(id: "claude-opus-5-5", name: "Opus 5.5", blurb: "Deep reasoning"),
        ClaudeModel(id: "claude-sonnet-5-5", name: "Sonnet 5.5", blurb: "Balanced and fast"),
        ClaudeModel(id: "claude-haiku-5-5", name: "Haiku 5.5", blurb: "Quickest, lightest")
    ]
    static let defaultID = "claude-sonnet-5-5"

    static func name(for id: String) -> String {
        all.first(where: { $0.id == id })?.name ?? id
    }
}

/// App-wide state shared between the tabs.
final class Store: ObservableObject {
    @Published var tab = 0
    @Published var apiKey: String = Keychain.load()

    func saveKey(_ value: String) {
        Keychain.save(value.trimmingCharacters(in: .whitespacesAndNewlines))
        apiKey = Keychain.load()
    }
}
