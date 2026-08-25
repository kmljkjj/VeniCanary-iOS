import Foundation
import WebKit
import Combine
import SwiftUI

/// Vendroid-style: Canary web + Vencord inject + petite console logs
final class WebModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var logs: [String] = []

    let canaryURL = URL(string: "https://canary.discord.com/login")!
    private let vencordURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!,
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!,
    ]

    private(set) var vencordJS: String = ""
    weak var webView: WKWebView?

    private let maxLogs = 200

    override init() {
        super.init()
        log("VeniCanary start — target Canary")
        Task { await preloadVencord() }
    }

    func log(_ msg: String) {
        let line = "[\(timeStamp())] \(msg)"
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
        print(line)
    }

    func clearLogs() {
        logs.removeAll()
        log("console cleared")
    }

    private func timeStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    @MainActor
    func attach(_ webView: WKWebView) {
        self.webView = webView
        log("WebView attached → load Canary")
        var req = URLRequest(url: canaryURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    func reload() {
        log("Reload Canary")
        webView?.reload()
    }

    func forceReinject() {
        guard let wv = webView else {
            log("ERROR no webview")
            return
        }
        log("Force re-inject Vencord…")
        // reset guard
        wv.evaluateJavaScript("window.__veniVencordInjected = false") { [weak self] _, _ in
            self?.injectVencord(into: wv, force: true)
        }
    }

    func preloadVencord() async {
        for url in vencordURLs {
            do {
                log("Fetch Vencord \(url.host ?? "")…")
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 30
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let s = String(data: data, encoding: .utf8), s.count > 500, code == 200 || code == 0 {
                    await MainActor.run {
                        self.vencordJS = s
                        self.log("Vencord loaded OK (\(s.count) chars) from \(url.host ?? "")")
                    }
                    return
                }
                log("Vencord bad response code=\(code) size=\(data.count)")
            } catch {
                log("Vencord fetch fail: \(error.localizedDescription)")
            }
        }
        log("ERROR could not load Vencord")
    }

    func injectVencord(into webView: WKWebView, force: Bool = false) {
        if vencordJS.isEmpty {
            log("Vencord empty — retry download")
            Task {
                await preloadVencord()
                await MainActor.run { self.injectVencord(into: webView, force: force) }
            }
            return
        }

        let wrapped = """
        (function(){
          if (!\(force ? "true" : "false") && window.__veniVencordInjected) {
            return 'already';
          }
          window.__veniVencordInjected = true;
          try {
            \(vencordJS)
            return 'ok';
          } catch(e) {
            return 'error:' + (e && e.message ? e.message : String(e));
          }
        })();
        """

        webView.evaluateJavaScript(wrapped) { [weak self] result, err in
            if let err = err {
                self?.log("inject error: \(err.localizedDescription)")
                return
            }
            let r = String(describing: result ?? "")
            if r.contains("already") {
                self?.log("Vencord already injected")
            } else if r.contains("error") {
                self?.log("inject JS \(r)")
            } else {
                self?.log("Vencord inject OK")
            }
        }
    }

    func pageFinished(url: String?) {
        log("didFinish \(url ?? "?")")
        DispatchQueue.main.async { self.isLoading = false }
        guard let wv = webView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.injectVencord(into: wv)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.injectVencord(into: wv)
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

        let bootstrap = "window.__veniCanary = true;"
        config.userContentController.addUserScript(
            WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

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
            self.model.log("navigation start…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.model.pageFinished(url: webView.url?.absoluteString)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            self.model.log("nav fail: \(error.localizedDescription)")
            DispatchQueue.main.async { self.model.isLoading = false }
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
            if host.contains("discord.com") || host.contains("discordapp.com") {
                decisionHandler(.allow)
                return
            }
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
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
