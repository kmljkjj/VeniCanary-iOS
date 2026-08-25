import Foundation
import WebKit
import Combine

final class WebModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var logs: [String] = []
    @Published var pageURL: String = "—"
    @Published var vencordStatus: String = "not loaded"
    @Published var injectCount: Int = 0

    private(set) var vencordJS: String = ""
    weak var webView: WKWebView?
    private let maxLogs = 400

    override init() {
        super.init()
        log("boot VeniCanary — desktop Canary")
        log("viewport scale \(String(format: "%.3f", AppConfig.viewportScale))")
        Task { await preloadVencord() }
    }

    func log(_ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(f.string(from: Date()))] \(msg)"
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
        print(line)
    }

    func clearLogs() {
        DispatchQueue.main.async { self.logs.removeAll() }
        log("console cleared")
    }

    @MainActor
    func attach(_ webView: WKWebView) {
        self.webView = webView
        log("WebView attached")
        var req = URLRequest(url: AppConfig.canaryURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    func reload() {
        log("reload")
        webView?.reload()
    }

    func goCanary() {
        log("navigate → canary/app")
        webView?.load(URLRequest(url: AppConfig.canaryURL))
    }

    func evalJS(_ code: String) {
        guard let wv = webView else {
            log("ERROR eval: no webview")
            return
        }
        log("> \(code.prefix(120))")
        wv.evaluateJavaScript(code) { [weak self] result, err in
            if let err = err {
                self?.log("eval error: \(err.localizedDescription)")
            } else {
                self?.log("< \(String(describing: result ?? "undefined").prefix(200))")
            }
        }
    }

    func forceReinject() {
        guard let wv = webView else {
            log("ERROR no webview")
            return
        }
        log("force reinject")
        wv.evaluateJavaScript("window.__veniVencordInjected=false;window.Vencord=undefined") { [weak self] _, _ in
            self?.injectVencord(into: wv, force: true)
        }
    }

    func checkVencord() {
        evalJS("(function(){try{return !!(window.Vencord||window.VencordNative||document.querySelector('[class*=\"vencord\"]'))}catch(e){return String(e)}})()")
    }

    func preloadVencord() async {
        await MainActor.run { self.vencordStatus = "downloading…" }
        for url in AppConfig.vencordURLs {
            do {
                log("GET \(url.absoluteString)")
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 45
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let s = String(data: data, encoding: .utf8), s.count > 1000, code == 200 {
                    await MainActor.run {
                        self.vencordJS = s
                        self.vencordStatus = "ready (\(s.count) chars)"
                        self.log("Vencord OK \(s.count) bytes from \(url.host ?? "")")
                    }
                    return
                }
                log("HTTP \(code) size=\(data.count)")
            } catch {
                log("fetch fail: \(error.localizedDescription)")
            }
        }
        await MainActor.run { self.vencordStatus = "FAILED" }
        log("ERROR Vencord download failed")
    }

    func desktopLayoutFixJS() -> String {
        let scale = AppConfig.viewportScale
        return """
        (function(){
          try {
            var meta = document.querySelector('meta[name=viewport]');
            if (!meta) {
              meta = document.createElement('meta');
              meta.name = 'viewport';
              document.head.appendChild(meta);
            }
            meta.content = 'width=1180, initial-scale=\(scale), maximum-scale=3, user-scalable=yes';
            var id = 'veni-desktop-css';
            if (!document.getElementById(id)) {
              var st = document.createElement('style');
              st.id = id;
              st.textContent = 'html, body { min-width: 1180px !important; }';
              document.head.appendChild(st);
            }
            return 'layout-ok scale=\(scale)';
          } catch(e) { return 'layout-err:'+e; }
        })();
        """
    }

    func applyDesktopLayout(into webView: WKWebView) {
        webView.evaluateJavaScript(desktopLayoutFixJS()) { [weak self] r, err in
            if let err = err { self?.log("layout err \(err.localizedDescription)") }
            else { self?.log("layout \(String(describing: r ?? ""))") }
        }
    }

    func injectVencord(into webView: WKWebView, force: Bool = false) {
        if vencordJS.isEmpty {
            log("Vencord empty — redownload")
            Task {
                await preloadVencord()
                await MainActor.run { self.injectVencord(into: webView, force: force) }
            }
            return
        }

        applyDesktopLayout(into: webView)

        let b64 = Data(vencordJS.utf8).base64EncodedString()
        let forceLit = force ? "true" : "false"
        let loader = """
        (function(){
          if (!\(forceLit) && window.__veniVencordInjected) return 'already';
          try {
            var old = document.getElementById('veni-vencord');
            if (old) old.remove();
            var el = document.createElement('script');
            el.id = 'veni-vencord';
            el.textContent = atob('\(b64)');
            (document.documentElement || document.head || document.body).appendChild(el);
            window.__veniVencordInjected = true;
            return 'ok';
          } catch(e) {
            return 'error:' + (e && e.message ? e.message : String(e));
          }
        })();
        """

        webView.evaluateJavaScript(loader) { [weak self] result, err in
            if let err = err {
                self?.log("inject error: \(err.localizedDescription)")
                return
            }
            let r = String(describing: result ?? "")
            DispatchQueue.main.async {
                self?.injectCount += 1
                if r.contains("already") {
                    self?.vencordStatus = "already injected"
                    self?.log("Vencord already")
                } else if r.hasPrefix("error") {
                    self?.vencordStatus = r
                    self?.log("inject \(r)")
                } else {
                    self?.vencordStatus = "injected OK"
                    self?.log("Vencord inject OK (#\(self?.injectCount ?? 0))")
                }
            }
        }
    }

    func pageFinished(url: String?) {
        let u = url ?? "?"
        DispatchQueue.main.async {
            self.pageURL = u
            self.isLoading = false
        }
        log("didFinish \(u)")
        guard webView != nil else { return }

        for delay in [0.3, 1.0, 2.5, 5.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let wv = self.webView else { return }
                self.applyDesktopLayout(into: wv)
                self.injectVencord(into: wv)
            }
        }
    }
}
