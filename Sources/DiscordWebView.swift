import SwiftUI
import WebKit

struct DiscordWebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let ucc = WKUserContentController()

        // 1) Desktop environment + viewport fit
        ucc.addUserScript(WKUserScript(
            source: Self.desktopBootScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        // 2) Vencord CSS
        if let css = model.vencordCSS, !css.isEmpty {
            ucc.addUserScript(WKUserScript(
                source: Self.cssInjectScript(css),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        // 3) Vencord JS (full browser build)
        if let js = model.vencordScript, !js.isEmpty {
            ucc.addUserScript(WKUserScript(
                source: Self.vencordWrapper(js),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
            context.coordinator.vencordSource = Self.vencordWrapper(js)
        }

        let config = WKWebViewConfiguration()
        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.minimumZoomScale = 0.2
        webView.scrollView.maximumZoomScale = 2.5
        webView.scrollView.delaysContentTouches = false
        webView.customUserAgent = Config.userAgent
        webView.isOpaque = false
        webView.backgroundColor = .black

        context.coordinator.webView = webView

        var request = URLRequest(url: Config.discordURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Scripts

    static let desktopBootScript = """
    (function () {
      if (window.__veniDesktop) return;
      window.__veniDesktop = true;

      var DESIGN_W = 1920;
      var DESIGN_H = 1080;

      function fit() {
        var sw = (window.visualViewport && visualViewport.width) || window.innerWidth || screen.width || 390;
        var sh = (window.visualViewport && visualViewport.height) || window.innerHeight || screen.height || 844;
        var s = Math.min(sw / DESIGN_W, sh / DESIGN_H);
        if (s < 0.25) s = 0.25;
        if (s > 0.6) s = 0.6;
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.content = 'width=' + DESIGN_W + ', initial-scale=' + s +
          ', minimum-scale=0.2, maximum-scale=2.5, user-scalable=yes, viewport-fit=cover';
      }

      // Desktop-class environment
      try {
        Object.defineProperty(navigator, 'userAgentData', {
          get: function () {
            return {
              brands: [{ brand: 'Chromium', version: '134' }, { brand: 'Not:A-Brand', version: '24' }],
              mobile: false,
              platform: 'Windows'
            };
          }
        });
      } catch (e) {}
      try {
        Object.defineProperty(navigator, 'platform', { get: function () { return 'Win32'; } });
        Object.defineProperty(navigator, 'maxTouchPoints', { get: function () { return 0; } });
      } catch (e) {}
      try {
        Object.defineProperty(window, 'innerWidth', { get: function () { return DESIGN_W; } });
        Object.defineProperty(window, 'outerWidth', { get: function () { return DESIGN_W; } });
        Object.defineProperty(window, 'innerHeight', { get: function () { return DESIGN_H; } });
        Object.defineProperty(window, 'outerHeight', { get: function () { return DESIGN_H; } });
      } catch (e) {}

      fit();
      document.addEventListener('DOMContentLoaded', fit);
      window.addEventListener('load', fit);
      setInterval(fit, 2000);
    })();
    """

    static func cssInjectScript(_ css: String) -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\\u2028", with: " ")
            .replacingOccurrences(of: "\\u2029", with: " ")
        // Use JSON encoding for safe string transport
        let data = try? JSONSerialization.data(withJSONObject: [escaped])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return """
        (function(){
          if (window.__veniCss) return;
          window.__veniCss = true;
          try {
            var css = \(json)[0];
            var s = document.createElement('style');
            s.id = 'vencord-css';
            s.textContent = css;
            (document.documentElement || document).appendChild(s);
            var obs = new MutationObserver(function(){
              if (!document.getElementById('vencord-css')) {
                (document.documentElement || document).appendChild(s);
              }
            });
            obs.observe(document.documentElement, {childList:true, subtree:true});
          } catch(e) {}
        })();
        """
    }

    static func vencordWrapper(_ js: String) -> String {
        // Guard + run Vencord browser build in page context
        return """
        (function(){
          if (window.__veniVencordInjected) return;
          window.__veniVencordInjected = true;
          try {
        """ + js + """
          } catch(e) {
            console.error('Vencord inject error', e);
          }
        })();
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebModel
        weak var webView: WKWebView?
        var vencordSource: String?
        private var reinjectCount = 0

        init(model: WebModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            reinjectVencord(into: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reinjectVencord(into: webView)
            // Fit viewport after paint
            webView.evaluateJavaScript("""
                (function(){
                  try {
                    var DESIGN_W=1920, DESIGN_H=1080;
                    var sw=(window.visualViewport&&visualViewport.width)||innerWidth||390;
                    var sh=(window.visualViewport&&visualViewport.height)||innerHeight||844;
                    var s=Math.min(sw/DESIGN_W, sh/DESIGN_H);
                    if(s<0.25)s=0.25; if(s>0.6)s=0.6;
                    var m=document.querySelector('meta[name=viewport]');
                    if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}
                    m.content='width='+DESIGN_W+', initial-scale='+s+', minimum-scale=0.2, maximum-scale=2.5, user-scalable=yes';
                    window.scrollTo(0,0);
                  }catch(e){}
                })();
            """, completionHandler: nil)
        }

        private func reinjectVencord(into webView: WKWebView) {
            guard let src = vencordSource, reinjectCount < 8 else { return }
            // If Vencord global missing, re-run script via evaluateJavaScript
            let check = "(function(){return !!(window.Vencord || window.__veniVencordInjected);})()"
            webView.evaluateJavaScript(check) { [weak self] result, _ in
                let ok = (result as? Bool) ?? false
                if !ok, let src = self?.vencordSource {
                    self?.reinjectCount += 1
                    webView.evaluateJavaScript(src, completionHandler: { _, err in
                        if let err = err {
                            print("Vencord eval error:", err.localizedDescription)
                        }
                    })
                }
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
                "discord.com", "discordapp.com", "discord.gg", "discordapp.net", "discord.co",
                "hcaptcha.com", "newassets.hcaptcha.com", "recaptcha.net",
                "google.com", "gstatic.com", "cloudflare.com", "cdn.discordapp.com",
                "github.com", "githubusercontent.com",
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
