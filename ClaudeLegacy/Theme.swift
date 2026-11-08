import SwiftUI

enum Theme {
    static let bg = Color.black
    static let surface = Color(red: 0.06, green: 0.06, blue: 0.065)
    static let surface2 = Color(red: 0.115, green: 0.115, blue: 0.125)
    static let accent = Provider.accent
    static let hairline = Color.white.opacity(0.09)
    static let dim = Color.white.opacity(0.55)
}

enum Models {
    static func name(for id: String) -> String {
        Provider.models.first(where: { $0.id == id })?.name ?? id
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

/// Errors and notes reported by the web tab, shown in Settings > Diagnostics.
final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()
    @Published var items: [String] = []

    func add(_ text: String) {
        DispatchQueue.main.async {
            self.items.append(text)
            if self.items.count > 100 { self.items.removeFirst() }
        }
    }

    func clear() { items.removeAll() }
}
