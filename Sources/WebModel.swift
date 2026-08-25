import Foundation
import WebKit
import Combine

/// Vendroid-style: load Discord web + inject Vencord.
/// Target = Canary (not stable).
final class WebModel: NSObject, ObservableObject {
    @Published var isLoading = true

    let canaryURL = URL(string: "https://canary.discord.com/login")!
    private let vencordURL = URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!
    // Fallback CDN-style build used by many web injectors
    private let vencordFallback = URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!

    private(set) var vencordJS: String = ""
    var webView: WKWebView?

    override init() {
        super.init()
        Task { await preloadVencord() }
    }

    @MainActor
    func attach(_ webView: WKWebView) {
        self.webView = webView
        var req = URLRequest(url: canaryURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    func preloadVencord() async {
        for url in [vencordFallback, vencordURL] {
            do {
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                if let s = String(data: data, encoding: .utf8), s.count > 500 {
                    await MainActor.run { self.vencordJS = s }
                    print("[VeniCanary] Vencord loaded from", url.absoluteString, s.count)
                    return
                }
            } catch {
                print("[VeniCanary] Vencord fetch fail", url, error)
            }
        }
    }

    func injectVencord(into webView: WKWebView) {
        guard !vencordJS.isEmpty else {
            // Retry fetch then inject
            Task {
                await preloadVencord()
                await MainActor.run { self.injectVencord(into: webView) }
            }
            return
        }
        // Guard against double-inject
        let wrapped = """
        (function(){
          if (window.__veniVencordInjected) return;
          window.__veniVencordInjected = true;
          try {
            \(vencordJS)
          } catch(e) { console.error('Vencord inject', e); }
        })();
        """
        webView.evaluateJavaScript(wrapped) { _, err in
            if let err = err { print("[VeniCanary] inject error", err) }
            else { print("[VeniCanary] Vencord injected") }
        }
    }
}

struct DiscordWebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        // Early inject user script (runs at document start when possible)
        let bootstrap = """
        window.__veniCanary = true;
        """
        let script = WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.17, green: 0.18, blue: 0.21, alpha: 1)
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        DispatchQueue.main.async {
            model.attach(wv)
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebModel
        init(model: WebModel) { self.model = model }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.model.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.model.isLoading = false }
            // Inject after page load (Vendroid-style)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.model.injectVencord(into: webView)
            }
            // Second pass for SPA route changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.model.injectVencord(into: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let host = url.host ?? ""
            // Keep discord / canary inside webview
            if host.contains("discord.com") || host.contains("discordapp.com") {
                decisionHandler(.allow)
                return
            }
            // External links → Safari
            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
