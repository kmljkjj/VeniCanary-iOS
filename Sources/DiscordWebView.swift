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
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let ucc = config.userContentController
        ucc.add(context.coordinator, name: "veniLog")

        let scale = AppConfig.viewportScale
        let w = AppConfig.viewportWidth

        // Early: viewport + error bridge
        let early = """
        (function(){
          window.__veniCanary = true;
          try {
            var m = document.querySelector('meta[name=viewport]');
            if (!m) { m = document.createElement('meta'); m.name='viewport'; document.documentElement.appendChild(m); }
            m.content = 'width=\(w), initial-scale=\(scale), maximum-scale=4, user-scalable=yes';
          } catch(e) {}
          function send(msg) {
            try { window.webkit.messageHandlers.veniLog.postMessage(String(msg)); } catch(e) {}
          }
          window.onerror = function(message, source, lineno, colno, error) {
            send('ERROR ' + message + ' @' + (source||'') + ':' + lineno + ':' + colno);
            return false;
          };
          window.addEventListener('unhandledrejection', function(ev) {
            send('ERROR unhandledrejection ' + (ev.reason && ev.reason.message ? ev.reason.message : String(ev.reason)));
          });
          var origErr = console.error;
          console.error = function() {
            try {
              var args = Array.prototype.slice.call(arguments).map(function(a){
                try { return typeof a === 'object' ? JSON.stringify(a) : String(a); } catch(e) { return String(a); }
              });
              send('ERROR console ' + args.join(' '));
            } catch(e) {}
            return origErr.apply(console, arguments);
          };
          var origWarn = console.warn;
          console.warn = function() {
            try {
              var args = Array.prototype.slice.call(arguments).map(String);
              send('WARN ' + args.join(' '));
            } catch(e) {}
            return origWarn.apply(console, arguments);
          };
        })();
        """
        ucc.addUserScript(WKUserScript(source: early, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.minimumZoomScale = 0.25
        wv.scrollView.maximumZoomScale = 4.0
        wv.scrollView.bouncesZoom = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.17, green: 0.18, blue: 0.21, alpha: 1)
        wv.customUserAgent = AppConfig.desktopUserAgent

        DispatchQueue.main.async {
            model.attach(wv)
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: WebModel
        init(model: WebModel) { self.model = model }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "veniLog" {
                model.handleJSMessage(message.body)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.model.isLoading = true }
            model.log("nav start")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.pageFinished(url: webView.url?.absoluteString)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.logError("nav fail: \(error.localizedDescription)")
            DispatchQueue.main.async { self.model.isLoading = false }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            model.logError("provisional fail: \(error.localizedDescription)")
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
