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

        // Viewport + desktop layout helpers (run very early)
        let boot = WKUserScript(
            source: Self.bootScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(boot)

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
        webView.scrollView.minimumZoomScale = 0.25
        webView.scrollView.maximumZoomScale = 3.0
        webView.scrollView.bouncesZoom = true
        webView.customUserAgent = Config.userAgent
        webView.isOpaque = false
        webView.backgroundColor = .black

        // Better hit-testing on small controls
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = true

        context.coordinator.webView = webView

        var request = URLRequest(url: Config.discordURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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

    /// Force desktop layout + scale page to fit the phone width
    static let bootScript = """
    (function () {
      try {
        // Pretend we have a wide desktop viewport
        var w = Math.max(1280, screen.width || 1280);

        function applyViewport() {
          var meta = document.querySelector('meta[name="viewport"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            (document.head || document.documentElement).appendChild(meta);
          }
          // Zoom out to fit desktop Discord on iPhone width
          meta.content =
            'width=' + w +
            ', initial-scale=0.35, minimum-scale=0.25, maximum-scale=3, user-scalable=yes';
        }

        applyViewport();

        // Keep re-applying (Discord rewrites head sometimes)
        var obs = new MutationObserver(function () { applyViewport(); });
        if (document.documentElement) {
          obs.observe(document.documentElement, { childList: true, subtree: true });
        }

        // Prefer desktop CSS breakpoints
        try {
          Object.defineProperty(window, 'innerWidth', { get: function() { return w; } });
          Object.defineProperty(window, 'outerWidth', { get: function() { return w; } });
        } catch (e) {}

        // Improve tap targets slightly
        var style = document.createElement('style');
        style.id = 'venicanary-touch';
        style.textContent = [
          'html, body { -webkit-text-size-adjust: 100% !important; }',
          '* { -webkit-tap-highlight-color: rgba(88,101,242,0.25); }',
          'button, a, [role="button"], [role="menuitem"], [class*="clickable"] {',
          '  cursor: pointer !important;',
          '}',
        ].join('\n');
        (document.documentElement || document).appendChild(style);
      } catch (e) {}
    })();
    """

    static func wrapVencord(js: String, css: String?) -> String {
        var parts: [String] = [bootScript]
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Extra zoom-out after load (pinches still work)
            let js = """
            (function(){
              try {
                var meta = document.querySelector('meta[name="viewport"]');
                if (meta) {
                  meta.content = 'width=1280, initial-scale=0.35, minimum-scale=0.25, maximum-scale=3, user-scalable=yes';
                }
                // Scroll to top-left
                window.scrollTo(0,0);
              } catch(e) {}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
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
