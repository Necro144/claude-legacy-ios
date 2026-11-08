import SwiftUI

@main
struct ClaudeLegacyApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                WebTab()
                    .tabItem { Label("Claude.ai", systemImage: "globe") }
                ChatTab()
                    .tabItem { Label("API chat", systemImage: "bubble.left.and.bubble.right") }
            }
        }
    }
}
