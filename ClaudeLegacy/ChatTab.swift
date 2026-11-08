import SwiftUI

struct MessageView: View {
    let message: Msg
    let canRegenerate: Bool
    let onRegenerate: () -> Void

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
                } else {
                    let blocks = parseBlocks(message.text)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        BlockView(block: block)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button { UIPasteboard.general.string = message.text } label: {
                    Label("Copy reply", systemImage: "doc.on.doc")
                }
                if canRegenerate {
                    Button { onRegenerate() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var chats: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chats.conversations.isEmpty {
                    Text("No chats yet.")
                        .foregroundColor(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(chats.conversations) { c in
                            Button {
                                chats.select(c.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.title).lineLimit(1).foregroundColor(.white)
                                        Text(c.updated.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(Theme.dim)
                                    }
                                    Spacer()
                                    if c.id == chats.currentID {
                                        Image(systemName: "checkmark").foregroundColor(Theme.accent)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { chats.conversations[$0].id }
                            ids.forEach { chats.delete($0) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("New chat") { chats.newChat(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ChatTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var chats: ChatStore
    @AppStorage("model") private var model = Provider.defaultModel
    @AppStorage("system") private var system = ""
    @AppStorage("temperature") private var temperature = 1.0
    @AppStorage("maxTokens") private var maxTokens = 4096
    @State private var draft = ""
    @State private var showHistory = false
    @FocusState private var focused: Bool

    private var config: ChatConfig {
        ChatConfig(key: store.apiKey, model: model, system: system, temperature: temperature, maxTokens: maxTokens)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    if store.apiKey.isEmpty {
                        setupPrompt
                    } else if chats.messages.isEmpty {
                        emptyState
                    } else {
                        messageList
                    }
                    if let error = chats.error {
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
            .navigationTitle(Models.name(for: model))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { chats.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(chats.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showHistory) { HistoryView() }
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill").font(.system(size: 34)).foregroundColor(Theme.accent)
            Text("Add your API key").font(.title3.bold())
            Text("Chat talks to \(Provider.name) directly with your own API key from \(Provider.keySite).")
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
            Text(Models.name(for: model)).font(.subheadline).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focused = false }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(chats.messages) { m in
                        MessageView(
                            message: m,
                            canRegenerate: !chats.busy && m.id == chats.messages.last?.id && m.role == "assistant",
                            onRegenerate: { chats.regenerate(config: config) }
                        )
                        .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chats.messages) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: chats.currentID) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var canSend: Bool {
        !store.apiKey.isEmpty && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(Provider.name)", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .disabled(store.apiKey.isEmpty)
                .padding(.leading, 14)
                .padding(.vertical, 10)
            Button {
                if chats.busy { chats.stop() } else { submit() }
            } label: {
                Image(systemName: chats.busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(chats.busy || canSend ? Theme.accent : Theme.surface2)
                    .clipShape(Circle())
            }
            .disabled(!chats.busy && !canSend)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chats.send(text, config: config)
    }
}
