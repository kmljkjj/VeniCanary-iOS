import Foundation
import WebKit
import Combine

final class WebModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var logs: [String] = []
    @Published var errors: [String] = []
    @Published var pageURL: String = "—"
    @Published var vencordStatus: String = "not loaded"
    @Published var injectCount: Int = 0

    private(set) var vencordJS: String = ""
    weak var webView: WKWebView?
    private let maxLogs = 400
    private let maxErrors = 150

    override init() {
        super.init()
        log("boot VeniCanary — desktop Canary")
        log("viewport scale \(String(format: "%.3f", AppConfig.viewportScale)) w=\(AppConfig.viewportWidth)")
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

    func logError(_ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(f.string(from: Date()))] \(msg)"
        DispatchQueue.main.async {
            self.errors.append(line)
            if self.errors.count > self.maxErrors {
                self.errors.removeFirst(self.errors.count - self.maxErrors)
            }
            self.logs.append("ERR " + line)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
        print("ERR", line)
    }

    func clearLogs() {
        DispatchQueue.main.async { self.logs.removeAll() }
        log("console cleared")
    }

    func clearErrors() {
        DispatchQueue.main.async { self.errors.removeAll() }
        log("errors cleared")
    }

    /// Texte à copier / envoyer pour debug
    func exportErrorsText() -> String {
        if errors.isEmpty { return "(aucune erreur capturée)" }
        return errors.joined(separator: "\n")
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
            logError("eval: no webview")
            return
        }
        log("> \(code.prefix(120))")
        wv.evaluateJavaScript(code) { [weak self] result, err in
            if let err = err {
                self?.logError("eval: \(err.localizedDescription)")
            } else {
                self?.log("< \(String(describing: result ?? "undefined").prefix(200))")
            }
        }
    }

    func forceReinject() {
        guard let wv = webView else {
            logError("reinject: no webview")
            return
        }
        log("force reinject")
        wv.evaluateJavaScript(
            "window.__veniVencordInjected=false; try{delete window.Vencord}catch(e){}"
        ) { [weak self] _, _ in
            self?.injectVencord(into: wv, force: true)
        }
    }

    func checkVencord() {
        evalJS("""
        (function(){
          try {
            return JSON.stringify({
              vencord: !!window.Vencord,
              plugins: window.Vencord && window.Vencord.Plugins ? Object.keys(window.Vencord.Plugins.plugins||{}).length : 0,
              injected: !!window.__veniVencordInjected,
              userAgent: navigator.userAgent.slice(0,80)
            });
          } catch(e) { return String(e); }
        })()
        """)
    }

    func preloadVencord() async {
        await MainActor.run { self.vencordStatus = "downloading…" }
        for url in AppConfig.vencordURLs {
            do {
                log("GET \(url.absoluteString)")
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 60
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
                logError("Vencord HTTP \(code) size=\(data.count)")
            } catch {
                logError("Vencord fetch: \(error.localizedDescription)")
            }
        }
        await MainActor.run { self.vencordStatus = "FAILED" }
        logError("Vencord download failed — check network / GitHub")
    }

    func desktopLayoutFixJS() -> String {
        let scale = AppConfig.viewportScale
        let w = AppConfig.viewportWidth
        return """
        (function(){
          try {
            var meta = document.querySelector('meta[name=viewport]');
            if (!meta) {
              meta = document.createElement('meta');
              meta.name = 'viewport';
              (document.head||document.documentElement).appendChild(meta);
            }
            meta.content = 'width=\(w), initial-scale=\(scale), maximum-scale=4, user-scalable=yes';
            var id = 'veni-desktop-css';
            if (!document.getElementById(id)) {
              var st = document.createElement('style');
              st.id = id;
              st.textContent = 'html,body{min-width:\(w)px!important;}';
              (document.head||document.documentElement).appendChild(st);
            }
            return 'layout-ok scale=\(scale)';
          } catch(e) { return 'layout-err:'+e; }
        })();
        """
    }

    func applyDesktopLayout(into webView: WKWebView) {
        webView.evaluateJavaScript(desktopLayoutFixJS()) { [weak self] r, err in
            if let err = err { self?.logError("layout: \(err.localizedDescription)") }
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

        // Method A: script element + base64 (avoids huge evaluate string issues)
        let b64 = Data(vencordJS.utf8).base64EncodedString()
        let forceLit = force ? "true" : "false"

        // Split base64 into chunks if needed for JS string limits — use array join
        let chunkSize = 500_000
        var parts: [String] = []
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: chunkSize, limitedBy: b64.endIndex) ?? b64.endIndex
            parts.append(String(b64[i..<j]))
            i = j
        }
        let partsJS = parts.map { "'\($0)'" }.joined(separator: ",")

        let loader = """
        (function(){
          if (!\(forceLit) && window.__veniVencordInjected) return 'already';
          try {
            var old = document.getElementById('veni-vencord');
            if (old) old.remove();
            var b64 = [\(partsJS)].join('');
            var code = atob(b64);
            var el = document.createElement('script');
            el.id = 'veni-vencord';
            el.textContent = code;
            (document.documentElement || document.head || document.body).appendChild(el);
            window.__veniVencordInjected = true;
            return 'ok:' + code.length;
          } catch(e) {
            try {
              // Method B: indirect eval
              var b64 = [\(partsJS)].join('');
              (0, eval)(atob(b64));
              window.__veniVencordInjected = true;
              return 'ok-eval';
            } catch(e2) {
              return 'error:' + (e2 && e2.message ? e2.message : String(e2));
            }
          }
        })();
        """

        webView.evaluateJavaScript(loader) { [weak self] result, err in
            if let err = err {
                self?.logError("inject: \(err.localizedDescription)")
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
                    self?.logError("inject \(r)")
                } else {
                    self?.vencordStatus = "injected OK"
                    self?.log("Vencord inject OK (#\(self?.injectCount ?? 0)) \(r)")
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

        for delay in [0.4, 1.2, 2.5, 5.0, 9.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let wv = self.webView else { return }
                self.applyDesktopLayout(into: wv)
                self.injectVencord(into: wv)
            }
        }
    }

    /// Appelé depuis le bridge JS (console.error / window.onerror)
    func handleJSMessage(_ body: Any) {
        let text: String
        if let s = body as? String {
            text = s
        } else if let d = body as? [String: Any] {
            text = (d["message"] as? String) ?? String(describing: d)
        } else {
            text = String(describing: body)
        }
        if text.lowercased().contains("error") || text.hasPrefix("ERROR") || text.contains("TypeError") || text.contains("ReferenceError") {
            logError(text)
        } else {
            log("js: \(text.prefix(300))")
        }
    }
}
