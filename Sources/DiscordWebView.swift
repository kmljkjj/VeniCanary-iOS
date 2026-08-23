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
        webView.scrollView.minimumZoomScale = 0.2
        webView.scrollView.maximumZoomScale = 2.5
        webView.scrollView.bouncesZoom = true
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = true
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

    /// Desktop layout + scale that fits BOTH width and height of the phone
    static let bootScript = """
    (function () {
      var DESIGN_W = 1280;
      var DESIGN_H = 800;

      function fitScale() {
        var sw = window.screen && screen.width ? screen.width : 390;
        var sh = window.screen && screen.height ? screen.height : 844;
        // Prefer visual viewport when available (more accurate on iOS)
        try {
          if (window.visualViewport) {
            sw = visualViewport.width || sw;
            sh = visualViewport.height || sh;
          }
        } catch (e) {}
        var sx = sw / DESIGN_W;
        var sy = sh / DESIGN_H;
        // Fit entire desktop UI on screen (no cropping top/bottom)
        var s = Math.min(sx, sy);
        // Keep readable but fully visible — clamp
        if (s < 0.28) s = 0.28;
        if (s > 0.55) s = 0.55;
        return { w: DESIGN_W, h: DESIGN_H, s: s };
      }

      function applyViewport() {
        var f = fitScale();
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.content =
          'width=' + f.w +
          ', height=' + f.h +
          ', initial-scale=' + f.s +
          ', minimum-scale=0.2, maximum-scale=2.5, user-scalable=yes, viewport-fit=cover';
      }

      function applyLayoutCSS() {
        var id = 'venicanary-fit';
        var el = document.getElementById(id);
        if (!el) {
          el = document.createElement('style');
          el.id = id;
          (document.documentElement || document).appendChild(el);
        }
        el.textContent = [
          'html, body {',
          '  margin: 0 !important;',
          '  padding: 0 !important;',
          '  width: 100% !important;',
          '  height: 100% !important;',
          '  overflow: auto !important;',
          '  -webkit-text-size-adjust: 100% !important;',
          '  touch-action: manipulation;',
          '}',
          /* Make bars easier to tap after downscale */
          'button, a, [role="button"], [role="menuitem"], [class*="clickable"], [class*="bar"] {',
          '  cursor: pointer !important;',
          '}',
        ].join('\n');
      }

      function applyAll() {
        try {
          applyViewport();
          applyLayoutCSS();
        } catch (e) {}
      }

      applyAll();

      // Discord rewrites DOM — re-apply
      try {
        var obs = new MutationObserver(function () { applyAll(); });
        obs.observe(document.documentElement, { childList: true, subtree: true });
      } catch (e) {}

      // Fake desktop width for CSS breakpoints
      try {
        Object.defineProperty(window, 'innerWidth', { get: function () { return DESIGN_W; } });
        Object.defineProperty(window, 'outerWidth', { get: function () { return DESIGN_W; } });
      } catch (e) {}

      window.addEventListener('resize', applyAll, { passive: true });
      window.addEventListener('orientationchange', function () {
        setTimeout(applyAll, 200);
      });
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
            // Re-fit after Discord paints
            let js = """
            (function(){
              try {
                var DESIGN_W = 1280, DESIGN_H = 800;
                var sw = (window.visualViewport && visualViewport.width) || screen.width || 390;
                var sh = (window.visualViewport && visualViewport.height) || screen.height || 844;
                var s = Math.min(sw / DESIGN_W, sh / DESIGN_H);
                if (s < 0.28) s = 0.28;
                if (s > 0.55) s = 0.55;
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                  meta = document.createElement('meta');
                  meta.name = 'viewport';
                  document.head.appendChild(meta);
                }
                meta.content = 'width=' + DESIGN_W + ', initial-scale=' + s +
                  ', minimum-scale=0.2, maximum-scale=2.5, user-scalable=yes, viewport-fit=cover';
                window.scrollTo(0, 0);
              } catch(e) {}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)

            // Second pass after layout settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                webView.evaluateJavaScript(js, completionHandler: nil)
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
