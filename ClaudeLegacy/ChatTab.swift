import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String   // "user" or "assistant"
    var text: String
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var busy = false
    @Published var error: String?
    private var task: Task<Void, Never>?

    func send(_ text: String, key: String, model: String, system: String) {
        messages.append(ChatMessage(role: "user", text: text))
        messages.append(ChatMessage(role: "assistant", text: ""))
        busy = true
        error = nil
        let history: [[String: String]] = messages
            .filter { !$0.text.isEmpty }
            .map { ["role": $0.role, "content": $0.text] }
        task = Task { await self.stream(history: history, key: key, model: model, system: system) }
    }

    func stop() { task?.cancel() }

    func reset() {
        task?.cancel()
        messages = []
        error = nil
        busy = false
    }

    private func stream(history: [[String: String]], key: String, model: String, system: String) async {
        defer {
            busy = false
            if let last = messages.last, last.role == "assistant", last.text.isEmpty { messages.removeLast() }
        }
        do {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            var body: [String: Any] = ["model": model, "max_tokens": 4096, "stream": true, "messages": history]
            if !system.isEmpty { body["system"] = system }
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

struct ChatTab: View {
    @StateObject private var chat = ChatModel()
    @AppStorage("model") private var model = "claude-sonnet-5-5"
    @AppStorage("system") private var system = ""
    @State private var apiKey = Keychain.load()
    @State private var draft = ""
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if apiKey.isEmpty {
                    VStack(spacing: 12) {
                        Text("Add your Anthropic API key to chat here.")
                        Button("Open settings") { showSettings = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    messageList
                }
                if let error = chat.error {
                    Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal).padding(.top, 6)
                }
                inputBar
            }
            .navigationTitle("Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { chat.reset() } label: { Image(systemName: "square.and.pencil") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.messages) { m in
                        bubble(m).id(m.id)
                    }
                }
                .padding()
            }
            .onChange(of: chat.messages) { _ in
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        let shown = (try? AttributedString(markdown: m.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m.text)
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(m.text.isEmpty ? AttributedString("...") : shown)
                .textSelection(.enabled)
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.2) : Color(UIColor.secondarySystemBackground))
                .cornerRadius(14)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Claude", text: $draft)
                .textFieldStyle(.roundedBorder)
                .disabled(apiKey.isEmpty)
            if chat.busy {
                Button { chat.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
            } else {
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(apiKey.isEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color(UIColor.systemBackground))
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        chat.send(text, key: apiKey, model: model, system: system)
    }

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Anthropic API key"),
                        footer: Text("Stored in this phone's Keychain. It is only sent to api.anthropic.com. Get one at console.anthropic.com.")) {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section(header: Text("Model")) {
                    TextField("Model id", text: $model)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section(header: Text("System prompt (optional)")) {
                    TextField("Instructions for every chat", text: $system)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        apiKey = Keychain.load()
                        showSettings = false
                    }
                }
            }
        }
    }
}
