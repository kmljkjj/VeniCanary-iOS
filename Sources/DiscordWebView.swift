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

        // Desktop viewport as early as possible
        let scale = AppConfig.viewportScale
        let early = """
        (function(){
          window.__veniCanary = true;
          var m = document.querySelector('meta[name=viewport]');
          if (!m) { m = document.createElement('meta'); m.name='viewport'; document.documentElement.appendChild(m); }
          m.content = 'width=1180, initial-scale=\(scale), maximum-scale=3, user-scalable=yes';
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: early, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.minimumZoomScale = 0.25
        wv.scrollView.maximumZoomScale = 3.0
        wv.scrollView.bounces = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.17, green: 0.18, blue: 0.21, alpha: 1)
        // CRITICAL: desktop Discord, not mobile web
        wv.customUserAgent = AppConfig.desktopUserAgent

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
            model.log("nav start")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.pageFinished(url: webView.url?.absoluteString)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.log("nav fail: \(error.localizedDescription)")
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
