import SwiftUI
import WebKit
import Combine

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    @Published var failed = false
    @Published var progress: Double = 0
    @Published var loading = false
    private var bag = Set<AnyCancellable>()

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(
            WKUserScript(source: WebShim.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "jsError")
        webView.customUserAgent = WebShim.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.overrideUserInterfaceStyle = .dark
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.indicatorStyle = .white
        if #available(iOS 15.0, *) { webView.underPageBackgroundColor = .black }

        let refresh = UIRefreshControl()
        refresh.tintColor = .white
        refresh.addTarget(self, action: #selector(pulled), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        webView.publisher(for: \.estimatedProgress)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.progress = $0 }
            .store(in: &bag)
        home()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let text = message.body as? String { ErrorLog.shared.add(text) }
    }

    @objc private func pulled() { reload() }

    func home() {
        failed = false
        webView.load(URLRequest(url: Provider.webURL))
    }

    func reload() {
        failed = false
        if webView.url == nil { home() } else { webView.reload() }
    }

    private func done(failure: Bool) {
        loading = false
        failed = failure
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        done(failure: false)
        let address = webView.url?.absoluteString ?? "?"
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak webView] in
            let probe = "document.body ? (document.body.innerText.length + ' characters, ' + document.body.children.length + ' elements') : 'no body'"
            webView?.evaluateJavaScript(probe) { result, _ in
                ErrorLog.shared.add("loaded \(address): \(result ?? "unknown")")
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
            ErrorLog.shared.add("HTTP \(http.statusCode) for \(http.url?.absoluteString ?? "?")")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        ErrorLog.shared.add("navigation failed: \(error.localizedDescription)")
        done(failure: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        ErrorLog.shared.add("page could not load: \(error.localizedDescription)")
        done(failure: true)
    }

    // Anything that wants a new window opens in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
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
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            WebContainer(webView: model.webView)

            if model.loading && model.progress < 1 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * model.progress, height: 2)
                }
                .frame(height: 2)
            }

            if model.failed {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.dim)
                    Text("Can't reach \(Provider.name)")
                        .font(.headline)
                    Text("Check your connection and try again.")
                        .font(.subheadline)
                        .foregroundColor(Theme.dim)
                    Button("Try again") { model.reload() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
