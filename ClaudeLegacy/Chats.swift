import SwiftUI

struct Msg: Identifiable, Codable, Equatable {
    var id = UUID()
    let role: String   // "user" or "assistant"
    var text: String
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "New chat"
    var messages: [Msg] = []
    var updated = Date()
}

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentID: UUID?
    @Published var busy = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private let storageKey = "chats.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = saved
            currentID = saved.first?.id
        }
    }

    var current: Conversation? { conversations.first(where: { $0.id == currentID }) }
    var messages: [Msg] { current?.messages ?? [] }

    private func save() {
        let keep = conversations.map { c -> Conversation in
            var copy = c
            copy.messages = c.messages.filter { !$0.text.isEmpty }
            return copy
        }
        if let data = try? JSONEncoder().encode(keep) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    private func mutate(_ id: UUID, _ change: (inout Conversation) -> Void) {
        if let i = conversations.firstIndex(where: { $0.id == id }) { change(&conversations[i]) }
    }

    func newChat() {
        stop()
        currentID = nil
        error = nil
    }

    func select(_ id: UUID) {
        stop()
        currentID = id
        error = nil
    }

    func delete(_ id: UUID) {
        if currentID == id { stop(); currentID = nil }
        conversations.removeAll(where: { $0.id == id })
        save()
    }

    func clearAll() {
        stop()
        conversations = []
        currentID = nil
        error = nil
        save()
    }

    func stop() { task?.cancel() }

    func send(_ text: String, config: ChatConfig) {
        guard !busy else { return }
        var id = currentID
        if id == nil {
            let c = Conversation(title: String(text.prefix(40)))
            conversations.insert(c, at: 0)
            currentID = c.id
            id = c.id
        }
        guard let cid = id else { return }
        mutate(cid) {
            $0.messages.append(Msg(role: "user", text: text))
            $0.messages.append(Msg(role: "assistant", text: ""))
            $0.updated = Date()
        }
        run(cid, config)
    }

    func regenerate(config: ChatConfig) {
        guard !busy, let cid = currentID else { return }
        mutate(cid) {
            if $0.messages.last?.role == "assistant" { $0.messages.removeLast() }
            $0.messages.append(Msg(role: "assistant", text: ""))
        }
        run(cid, config)
    }

    private func run(_ cid: UUID, _ config: ChatConfig) {
        busy = true
        error = nil
        let history: [[String: String]] = (conversations.first(where: { $0.id == cid })?.messages ?? [])
            .filter { !$0.text.isEmpty }
            .map { ["role": $0.role, "content": $0.text] }
        task = Task { await self.stream(cid, history: history, config: config) }
    }

    private func stream(_ cid: UUID, history: [[String: String]], config: ChatConfig) async {
        defer {
            busy = false
            mutate(cid) { c in
                if let last = c.messages.last, last.role == "assistant", last.text.isEmpty { c.messages.removeLast() }
            }
            save()
        }
        do {
            let request = try Provider.request(config, history: history)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode != 200 {
                var raw = ""
                for try await line in bytes.lines { raw += line }
                error = "Error \(http.statusCode): \(Provider.apiMessage(raw))"
                return
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                switch Provider.chunk(from: payload) {
                case .text(let piece):
                    mutate(cid) { c in
                        if !c.messages.isEmpty { c.messages[c.messages.count - 1].text += piece }
                    }
                case .error(let message):
                    error = message
                case .done:
                    return
                case .skip:
                    break
                }
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }
}
