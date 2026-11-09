import SwiftUI
import WebKit
import Combine
import AVFoundation

/// The view controller currently on top, used to present native alerts and the share sheet.
func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
}

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let webView: WKWebView
    @Published var failed = false
    @Published var progress: Double = 0
    @Published var loading = false
    @Published var popup: WKWebView?
    @Published var blankNote: String?
    private var bag = Set<AnyCancellable>()
    private var downloadFiles: [ObjectIdentifier: URL] = [:]
    private var probeToken = 0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // TEST_NOSHIM is only used by the automated simulator test.
        if ProcessInfo.processInfo.environment["TEST_NOSHIM"] == nil {
            config.userContentController.addUserScript(
                WKUserScript(source: WebShim.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // Let music play with the silent switch on and keep going in the background.
        // TEST_NOAUDIO is only used by the automated simulator test.
        if ProcessInfo.processInfo.environment["TEST_NOAUDIO"] == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "jsError")
        style(webView)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.indicatorStyle = .white

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

    /// Looks and identifies like a normal Safari window, on a black canvas.
    private func style(_ view: WKWebView) {
        // TEST_UA is only used by the automated simulator test.
        view.customUserAgent = ProcessInfo.processInfo.environment["TEST_UA"] ?? WebShim.userAgent
        view.navigationDelegate = self
        view.uiDelegate = self
        view.overrideUserInterfaceStyle = .dark
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.underPageBackgroundColor = .black
    }

    private func isMain(_ view: WKWebView) -> Bool { view === webView }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let text = message.body as? String { ErrorLog.shared.add(text) }
    }

    @objc private func pulled() { reload() }

    func home() {
        failed = false
        blankNote = nil
        // TEST_URL is only used by the automated simulator test.
        let override = ProcessInfo.processInfo.environment["TEST_URL"].flatMap { URL(string: $0) }
        webView.load(URLRequest(url: override ?? Provider.webURL))
    }

    func reload() {
        failed = false
        blankNote = nil
        if webView.url == nil { home() } else { webView.reload() }
    }

    func closePopup() {
        popup?.stopLoading()
        popup = nil
    }

    private func done(failure: Bool) {
        loading = false
        failed = failure
        webView.scrollView.refreshControl?.endRefreshing()
    }

    // MARK: blank page detection

    private func scheduleProbes(for view: WKWebView) {
        probeToken += 1
        let token = probeToken
        for delay in [4.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                guard let self = self, let view = view, token == self.probeToken else { return }
                // text length | child elements | images, buttons, links, canvases and the like
                let probe = "document.body ? (document.body.innerText.trim().length + '|' + document.body.children.length + '|' + document.querySelectorAll('img,canvas,video,iframe,svg,input,button,a').length) : '-1|0|0'"
                view.evaluateJavaScript(probe) { result, _ in
                    let text = (result as? String) ?? "?"
                    let parts = text.split(separator: "|").map { Int($0) ?? 0 }
                    let length = parts.first ?? 0
                    let things = parts.count > 2 ? parts[2] : 0
                    let address = view.url?.absoluteString ?? "?"
                    ErrorLog.shared.add("check \(address): \(text)")
                    DispatchQueue.main.async {
                        if length < 25 && things == 0 {
                            self.blankNote = "\(address)\nbody: \(text)"
                        } else {
                            self.blankNote = nil
                        }
                    }
                }
            }
        }
    }

    func copyDetails() {
        let recent = ErrorLog.shared.items.suffix(12).joined(separator: "\n")
        UIPasteboard.general.string = "Blank page\n\(blankNote ?? "")\n\nRecent messages:\n\(recent)"
    }

    // MARK: navigation

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if isMain(webView) { loading = true; blankNote = nil }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isMain(webView) else { return }
        done(failure: false)
        scheduleProbes(for: webView)
        runTestScripts()
    }

    // The next two pieces are only used by the automated simulator test (TEST_JS_FILE and friends).
    private var testStarted = false

    private func runTestScripts() {
        let env = ProcessInfo.processInfo.environment
        guard !testStarted, let first = env["TEST_JS_FILE"], let step1 = try? String(contentsOfFile: first) else { return }
        testStarted = true
        let step2 = env["TEST_JS2_FILE"].flatMap { try? String(contentsOfFile: $0) } ?? "'none'"
        let target = env["TEST_OUT"] ?? (NSTemporaryDirectory() + "test-result.txt")
        let wait = Double(env["TEST_WAIT"] ?? "") ?? 14
        var lines: [String] = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            self.webView.evaluateJavaScript(step1) { result, error in
                lines.append("step1: " + (result.map { String(describing: $0) } ?? error?.localizedDescription ?? "nil"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            self.webView.evaluateJavaScript(step2) { result, error in
                lines.append("step2: " + (result.map { String(describing: $0) } ?? error?.localizedDescription ?? "nil"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 2) {
            let nl = String(UnicodeScalar(10))
            let logText = ErrorLog.shared.items.joined(separator: nl)
            let text = lines.joined(separator: nl) + nl + nl + "log:" + nl + logText
            try? text.write(toFile: target, atomically: true, encoding: .utf8)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            UIApplication.shared.open(url)      // mail, phone, app links open in their own apps
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            if http.statusCode >= 400 {
                ErrorLog.shared.add("HTTP \(http.statusCode) for \(http.url?.absoluteString ?? "?")")
            }
            let disposition = (http.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            if disposition.hasPrefix("attachment") {
                decisionHandler(.download)
                return
            }
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        ErrorLog.shared.add("navigation failed: \(error.localizedDescription)")
        if isMain(webView) { done(failure: true) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        // A navigation that turned into a download also lands here with code 102; that is not a failure.
        if (error as NSError).domain == "WebKitErrorDomain" && (error as NSError).code == 102 { return }
        ErrorLog.shared.add("page could not load: \(error.localizedDescription)")
        if isMain(webView) { done(failure: true) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ErrorLog.shared.add("the page process stopped; reloading")
        if isMain(webView) { reload() }
    }

    // MARK: windows opened by the page (sign-in popups)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // A plain link that asks for a new tab just opens in this view.
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            webView.load(navigationAction.request)
            return nil
        }
        // A script-opened window (window.open) gets a real window, so sign-in can talk back to the page.
        let window = WKWebView(frame: .zero, configuration: configuration)
        style(window)
        popup = window
        return window
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { popup = nil }
    }

    // MARK: JavaScript dialogs, as native alerts

    private func show(_ alert: UIAlertController, otherwise: () -> Void) {
        if let top = topViewController() { top.present(alert, animated: true) } else { otherwise() }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        show(alert, otherwise: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        show(alert, otherwise: { completionHandler(false) })
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        show(alert, otherwise: { completionHandler(nil) })
    }

    // Microphone and camera: only for the site this app is for, and iOS still asks the user.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix(Provider.host) ? .grant : .deny)
    }

    // MARK: downloads, handed to the iOS share sheet

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(suggestedFilename)
        downloadFiles[ObjectIdentifier(download)] = file
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadFiles.removeValue(forKey: ObjectIdentifier(download)) else { return }
        DispatchQueue.main.async {
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            if let top = topViewController() {
                sheet.popoverPresentationController?.sourceView = top.view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1)
                top.present(sheet, animated: true)
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadFiles.removeValue(forKey: ObjectIdentifier(download))
        ErrorLog.shared.add("download failed: \(error.localizedDescription)")
    }
}

struct WebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct PopupSheet: View {
    let webView: WKWebView
    let close: () -> Void

    var body: some View {
        NavigationStack {
            WebContainer(webView: webView)
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle(webView.url?.host ?? "Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.black, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } }
                }
        }
        .preferredColorScheme(.dark)
    }
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

            if model.blankNote != nil && !model.failed {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("This page came up blank")
                            .font(.headline)
                        Text("Try reloading. If it keeps happening, copy the details and send them to Necro.")
                            .font(.footnote)
                            .foregroundColor(Theme.dim)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button("Reload") { model.reload() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                            Button("Copy details") { model.copyDetails() }
                                .buttonStyle(.bordered)
                                .tint(.white)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(12)
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: Binding(
            get: { model.popup != nil },
            set: { if !$0 { model.closePopup() } })) {
            if let popup = model.popup {
                PopupSheet(webView: popup) { model.closePopup() }
            }
        }
    }
}
