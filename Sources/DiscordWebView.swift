import SwiftUI
import WebKit

struct DiscordWebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Inject as early as possible once script is ready
        if let js = model.vencordScript {
            let script = WKUserScript(
                source: Self.wrapVencord(js: js, css: model.vencordCSS),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.customUserAgent = Config.userAgent
        webView.isOpaque = false
        webView.backgroundColor = .black

        context.coordinator.webView = webView

        var request = URLRequest(url: Config.discordURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // When Vencord finishes downloading after first frame, inject + reload once
        if let js = model.vencordScript, !context.coordinator.didInjectVencord {
            context.coordinator.didInjectVencord = true
            let wrapped = Self.wrapVencord(js: js, css: model.vencordCSS)
            let script = WKUserScript(
                source: wrapped,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            webView.configuration.userContentController.addUserScript(script)
            webView.reload()
        }
    }

    static func wrapVencord(js: String, css: String?) -> String {
        var parts: [String] = []
        if let css, !css.isEmpty {
            let escaped = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "${", with: "\\${")
            parts.append("""
            (function(){
              try {
                var s = document.createElement('style');
                s.id = 'vencord-css';
                s.textContent = `\(escaped)`;
                (document.documentElement || document.head || document).appendChild(s);
              } catch(e) {}
            })();
            """)
        }
        parts.append(js)
        return parts.joined(separator: "\n")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebModel
        weak var webView: WKWebView?
        var didInjectVencord = false

        init(model: WebModel) {
            self.model = model
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
            // Keep discord / vencord / captcha in-app; open others outside
            let host = url.host?.lowercased() ?? ""
            let allowed = [
                "discord.com", "discordapp.com", "discord.gg",
                "discordapp.net", "discord.co", "hcaptcha.com",
                "newassets.hcaptcha.com", "recaptcha.net", "google.com",
                "gstatic.com", "cloudflare.com", "cdn.discordapp.com",
            ]
            if allowed.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
