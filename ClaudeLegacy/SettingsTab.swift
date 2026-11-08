import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var chat: ChatModel
    @AppStorage("model") private var model = ClaudeModels.defaultID
    @AppStorage("system") private var system = ""
    @AppStorage("temperature") private var temperature = 1.0
    @AppStorage("maxTokens") private var maxTokens = 4096
    @State private var keyDraft = ""
    @State private var custom = ""
    @State private var confirmClear = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var isCustom: Bool { !ClaudeModels.all.contains(where: { $0.id == model }) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Claude version") {
                    ForEach(ClaudeModels.all) { m in
                        Button {
                            model = m.id
                            custom = ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).foregroundColor(.white)
                                    Text(m.blurb).font(.caption).foregroundColor(Theme.dim)
                                }
                                Spacer()
                                if model == m.id { Image(systemName: "checkmark").foregroundColor(Theme.accent) }
                            }
                        }
                    }
                    HStack {
                        TextField("Other model id", text: $custom)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { if !custom.isEmpty { model = custom } }
                        if isCustom { Image(systemName: "checkmark").foregroundColor(Theme.accent) }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Conversation") {
                    TextField("System prompt (optional)", text: $system, axis: .vertical)
                        .lineLimit(1...5)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Creativity")
                            Spacer()
                            Text(String(format: "%.1f", temperature)).foregroundColor(Theme.dim)
                        }
                        Slider(value: $temperature, in: 0...1, step: 0.1).tint(Theme.accent)
                    }
                    Picker("Longest reply", selection: $maxTokens) {
                        Text("1,024 tokens").tag(1024)
                        Text("2,048 tokens").tag(2048)
                        Text("4,096 tokens").tag(4096)
                        Text("8,192 tokens").tag(8192)
                    }
                    Button("Clear conversation", role: .destructive) { confirmClear = true }
                        .disabled(chat.messages.isEmpty)
                }
                .listRowBackground(Theme.surface)

                Section {
                    SecureField(store.apiKey.isEmpty ? "sk-ant-..." : "Key saved", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        store.saveKey(keyDraft)
                        keyDraft = ""
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !store.apiKey.isEmpty {
                        Button("Remove key", role: .destructive) { store.saveKey("") }
                    }
                } header: {
                    Text("API key")
                } footer: {
                    Text("Used by the Chat tab. Kept in this iPhone's Keychain and sent only to api.anthropic.com. Get one at console.anthropic.com.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    HStack {
                        Image(systemName: "sparkle")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude Legacy").font(.headline)
                            Text("Version \(version)").font(.caption).foregroundColor(Theme.dim)
                        }
                    }
                    HStack { Text("Made by"); Spacer(); Text("Necro").foregroundColor(Theme.accent) }
                    HStack { Text("Runs on"); Spacer(); Text("iOS 16 and up").foregroundColor(Theme.dim) }
                } header: {
                    Text("About")
                } footer: {
                    Text("An unofficial app. Not affiliated with or endorsed by Anthropic.")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbarBackground(.black, for: .navigationBar)
            .confirmationDialog("Clear this conversation?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { chat.reset() }
            }
        }
    }
}
