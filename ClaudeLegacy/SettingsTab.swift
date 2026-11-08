import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var chats: ChatStore
    @ObservedObject private var log = ErrorLog.shared
    @AppStorage("model") private var model = Provider.defaultModel
    @AppStorage("system") private var system = ""
    @AppStorage("temperature") private var temperature = 1.0
    @AppStorage("maxTokens") private var maxTokens = 4096
    @AppStorage("spoofUA") private var spoofUA = true
    @State private var keyDraft = ""
    @State private var custom = ""
    @State private var confirmClear = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var isCustom: Bool { !Provider.models.contains(where: { $0.id == model }) }

    var body: some View {
        NavigationStack {
            Form {
                Section("\(Provider.name) version") {
                    ForEach(Provider.models) { m in
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
                    if Provider.supportsTemperature {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Creativity")
                                Spacer()
                                Text(String(format: "%.1f", temperature)).foregroundColor(Theme.dim)
                            }
                            Slider(value: $temperature, in: 0...1, step: 0.1).tint(Theme.accent)
                        }
                    }
                    Picker("Longest reply", selection: $maxTokens) {
                        Text("1,024 tokens").tag(1024)
                        Text("2,048 tokens").tag(2048)
                        Text("4,096 tokens").tag(4096)
                        Text("8,192 tokens").tag(8192)
                    }
                    Button("Delete all chats", role: .destructive) { confirmClear = true }
                        .disabled(chats.conversations.isEmpty)
                }
                .listRowBackground(Theme.surface)

                Section {
                    SecureField(store.apiKey.isEmpty ? Provider.keyPlaceholder : "Key saved", text: $keyDraft)
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
                    Text("Used by the Chat tab. Kept in this iPhone's Keychain and sent only to \(Provider.apiHost). Get one at \(Provider.keySite).")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Compatibility mode", isOn: $spoofUA).tint(Theme.accent)
                    NavigationLink {
                        PageErrorsView()
                    } label: {
                        HStack {
                            Text("Page errors")
                            Spacer()
                            Text("\(log.items.count)").foregroundColor(Theme.dim)
                        }
                    }
                } header: {
                    Text("\(Provider.name) tab")
                } footer: {
                    Text("Compatibility mode presents the app as a newer Safari so the site stops saying this device is out of date. Close and reopen the app after changing it. Page errors lists problems the page reports.")
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
                            Text("\(Provider.name) Legacy").font(.headline)
                            Text("Version \(version)").font(.caption).foregroundColor(Theme.dim)
                        }
                    }
                    HStack { Text("Made by"); Spacer(); Text("Necro").foregroundColor(Theme.accent) }
                    HStack { Text("Runs on"); Spacer(); Text("iOS 16 and up").foregroundColor(Theme.dim) }
                } header: {
                    Text("About")
                } footer: {
                    Text("An unofficial app. Not affiliated with or endorsed by the company behind \(Provider.name).")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbarBackground(.black, for: .navigationBar)
            .confirmationDialog("Delete every chat?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { chats.clearAll() }
            }
        }
    }
}

struct PageErrorsView: View {
    @ObservedObject private var log = ErrorLog.shared

    var body: some View {
        Group {
            if log.items.isEmpty {
                Text("No errors so far.")
                    .foregroundColor(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(log.items.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .listRowBackground(Theme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Page errors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { UIPasteboard.general.string = log.items.joined(separator: "\n\n") } label: {
                        Label("Copy all", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) { log.clear() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(log.items.isEmpty)
            }
        }
    }
}
