import SwiftUI
import WebKit

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var failure: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        home()
    }

    func home() {
        failure = nil
        webView.load(URLRequest(url: URL(string: "https://claude.ai")!))
    }

    // Links that want a new window open in the same view instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        failure = nil
    }
}

struct WebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebTab: View {
    @StateObject private var model = WebModel()

    var body: some View {
        VStack(spacing: 0) {
            WebContainer(webView: model.webView)
            if let failure = model.failure {
                Text(failure).font(.footnote).foregroundColor(.red).padding(6)
            }
            HStack {
                Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button { model.webView.goForward() } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Spacer()
                Button { model.home() } label: { Image(systemName: "house") }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }
}
