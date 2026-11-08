import SwiftUI

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let role: String   // "user" or "assistant"
    var text: String
}

struct ChatConfig {
    var key: String
    var model: String
    var system: String
    var temperature: Double
    var maxTokens: Int
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var busy = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private let saveKey = "chat.history"

    init() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = saved
        }
    }

    private func persist() {
        let keep = messages.filter { !$0.text.isEmpty }
        if let data = try? JSONEncoder().encode(keep) { UserDefaults.standard.set(data, forKey: saveKey) }
    }

    func send(_ text: String, config: ChatConfig) {
        messages.append(ChatMessage(role: "user", text: text))
        messages.append(ChatMessage(role: "assistant", text: ""))
        busy = true
        error = nil
        let history: [[String: String]] = messages
            .filter { !$0.text.isEmpty }
            .map { ["role": $0.role, "content": $0.text] }
        task = Task { await self.stream(history: history, config: config) }
    }

    func stop() { task?.cancel() }

    func reset() {
        task?.cancel()
        messages = []
        error = nil
        busy = false
        persist()
    }

    private func stream(history: [[String: String]], config: ChatConfig) async {
        defer {
            busy = false
            if let last = messages.last, last.role == "assistant", last.text.isEmpty { messages.removeLast() }
            persist()
        }
        do {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue(config.key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            var body: [String: Any] = [
                "model": config.model,
                "max_tokens": config.maxTokens,
                "temperature": config.temperature,
                "stream": true,
                "messages": history
            ]
            if !config.system.isEmpty { body["system"] = config.system }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode != 200 {
                var raw = ""
                for try await line in bytes.lines { raw += line }
                error = "Error \(http.statusCode): \(Self.apiMessage(raw))"
                return
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = obj["type"] as? String else { continue }
                if type == "content_block_delta",
                   let delta = obj["delta"] as? [String: Any],
                   let piece = delta["text"] as? String,
                   !messages.isEmpty {
                    messages[messages.count - 1].text += piece
                } else if type == "error" {
                    error = Self.apiMessage(payload)
                }
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }

    private static func apiMessage(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let message = err["message"] as? String { return message }
        return raw
    }
}

// MARK: - Views

struct CodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption)
                    .foregroundColor(Theme.dim)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .foregroundColor(Theme.dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().background(Theme.hairline)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MessageView: View {
    let message: ChatMessage

    private struct Part: Identifiable {
        let id: Int
        let isCode: Bool
        let language: String
        let body: String
    }

    private var parts: [Part] {
        let pieces = message.text.components(separatedBy: "```")
        var out: [Part] = []
        for (i, piece) in pieces.enumerated() {
            if i % 2 == 1 {
                var lines = piece.components(separatedBy: "\n")
                let lang = lines.isEmpty ? "" : lines.removeFirst().trimmingCharacters(in: .whitespaces)
                out.append(Part(id: i, isCode: true, language: lang,
                                body: lines.joined(separator: "\n").trimmingCharacters(in: .newlines)))
            } else {
                let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(Part(id: i, isCode: false, language: "", body: trimmed)) }
            }
        }
        return out
    }

    private func rich(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 56)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if message.text.isEmpty {
                    ProgressView().tint(Theme.accent)
                }
                ForEach(parts) { part in
                    if part.isCode {
                        CodeBlock(language: part.language, code: part.body)
                    } else {
                        Text(rich(part.body)).textSelection(.enabled).lineSpacing(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button { UIPasteboard.general.string = message.text } label: { Label("Copy reply", systemImage: "doc.on.doc") }
            }
        }
    }
}

struct ChatTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var chat: ChatModel
    @AppStorage("model") private var model = ClaudeModels.defaultID
    @AppStorage("system") private var system = ""
    @AppStorage("temperature") private var temperature = 1.0
    @AppStorage("maxTokens") private var maxTokens = 4096
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    if store.apiKey.isEmpty {
                        setupPrompt
                    } else if chat.messages.isEmpty {
                        emptyState
                    } else {
                        messageList
                    }
                    if let error = chat.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                    }
                    inputBar
                }
            }
            .navigationTitle(ClaudeModels.name(for: model))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { chat.reset() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(chat.messages.isEmpty)
                }
            }
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill").font(.system(size: 34)).foregroundColor(Theme.accent)
            Text("Add your API key").font(.title3.bold())
            Text("Chat talks to Claude directly with your own Anthropic API key.")
                .font(.subheadline).foregroundColor(Theme.dim).multilineTextAlignment(.center)
            Button("Open Settings") { store.tab = 2 }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 38)).foregroundColor(Theme.accent)
            Text("How can I help?").font(.title2.bold())
            Text(ClaudeModels.name(for: model)).font(.subheadline).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { focused = false }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(chat.messages) { m in
                        MessageView(message: m).id(m.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages) { _ in
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var canSend: Bool {
        !store.apiKey.isEmpty && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Claude", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .disabled(store.apiKey.isEmpty)
                .padding(.leading, 14)
                .padding(.vertical, 10)
            Button {
                if chat.busy { chat.stop() } else { submit() }
            } label: {
                Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(chat.busy || canSend ? Theme.accent : Theme.surface2)
                    .clipShape(Circle())
            }
            .disabled(!chat.busy && !canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        chat.send(text, config: ChatConfig(key: store.apiKey, model: model, system: system,
                                           temperature: temperature, maxTokens: maxTokens))
    }
}
