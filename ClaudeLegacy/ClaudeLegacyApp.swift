import SwiftUI

@main
struct ClaudeLegacyApp: App {
    @StateObject private var store = Store()
    @StateObject private var chat = ChatModel()

    init() {
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = .black
        tabs.shadowColor = UIColor.white.withAlphaComponent(0.09)
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .black
        bar.shadowColor = UIColor.white.withAlphaComponent(0.09)
        bar.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $store.tab) {
                WebTab()
                    .tabItem { Label("Claude", systemImage: "sparkles") }
                    .tag(0)
                ChatTab()
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                    .tag(1)
                SettingsTab()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(2)
            }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .environmentObject(store)
            .environmentObject(chat)
        }
    }
}
