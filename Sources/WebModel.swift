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

    private let ignoreErrorSubstrings = [
        "ResizeObserver loop",
        "Non-Error promise rejection",
        "ResizeObserver",
    ]

    override init() {
        super.init()
        log("boot VeniCanary — desktop Canary")
        log("scale=\(String(format: "%.3f", AppConfig.viewportScale))")
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
        for ig in ignoreErrorSubstrings where msg.contains(ig) {
            log("(ignored) \(msg.prefix(80))")
            return
        }
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

    func exportErrorsText() -> String {
        errors.isEmpty ? "(aucune erreur capturée)" : errors.joined(separator: "\n")
    }

    @MainActor
    func attach(_ webView: WKWebView) {
        self.webView = webView
        log("WebView attached")
        var req = URLRequest(url: AppConfig.canaryURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    func reload() { log("reload"); webView?.reload() }

    func goCanary() {
        log("navigate → canary/app")
        webView?.load(URLRequest(url: AppConfig.canaryURL))
    }

    /// Scroll / pan vers le HAUT de la page Discord
    func scrollToTop() {
        guard let wv = webView else { return }
        log("→ Haut")
        // 1) UIScrollView natif
        DispatchQueue.main.async {
            let sv = wv.scrollView
            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: -sv.adjustedContentInset.top), animated: true)
        }
        // 2) JS fallback (window + conteneurs Discord)
        wv.evaluateJavaScript("""
        (function(){
          try {
            window.scrollTo({top:0,left:0,behavior:'smooth'});
            document.documentElement.scrollTop = 0;
            document.body.scrollTop = 0;
            var nodes = document.querySelectorAll('[class*="scroller"], [class*="auto-"], main, #app-mount');
            for (var i=0;i<nodes.length;i++) {
              try { nodes[i].scrollTop = 0; } catch(e){}
            }
            return 'top-ok';
          } catch(e) { return String(e); }
        })();
        """, completionHandler: nil)
    }

    /// Scroll / pan vers le BAS (barre utilisateur, input, etc.)
    func scrollToBottom() {
        guard let wv = webView else { return }
        log("→ Bas")
        DispatchQueue.main.async {
            let sv = wv.scrollView
            let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: maxY), animated: true)
        }
        wv.evaluateJavaScript("""
        (function(){
          try {
            var h = Math.max(
              document.body.scrollHeight||0,
              document.documentElement.scrollHeight||0
            );
            window.scrollTo({top:h,left:0,behavior:'smooth'});
            document.documentElement.scrollTop = h;
            document.body.scrollTop = h;
            var nodes = document.querySelectorAll('[class*="scroller"], [class*="auto-"]');
            for (var i=0;i<nodes.length;i++) {
              try {
                var el = nodes[i];
                el.scrollTop = el.scrollHeight;
              } catch(e){}
            }
            return 'bottom-ok';
          } catch(e) { return String(e); }
        })();
        """, completionHandler: nil)
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
                self?.log("< \(String(describing: result ?? "undefined").prefix(300))")
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
            var p = 0;
            try { p = Object.keys((window.Vencord&&window.Vencord.Plugins&&window.Vencord.Plugins.plugins)||{}).length; } catch(e){}
            return JSON.stringify({
              vencord: typeof window.Vencord !== 'undefined',
              injectedFlag: !!window.__veniVencordInjected,
              scriptTag: !!document.getElementById('veni-vencord'),
              plugins: p,
              webpack: !!(window.webpackChunkdiscord_app || window.webpackChunk)
            });
          } catch(e) { return 'err:'+e; }
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
                        self.log("Vencord OK \(s.count) bytes")
                    }
                    return
                }
                logError("Vencord HTTP \(code) size=\(data.count)")
            } catch {
                logError("Vencord fetch: \(error.localizedDescription)")
            }
        }
        await MainActor.run { self.vencordStatus = "FAILED" }
        logError("Vencord download failed")
    }

    func desktopLayoutFixJS() -> String {
        let scale = AppConfig.viewportScale
        let w = AppConfig.viewportWidth
        let h = Int(AppConfig.layoutHeight)
        return """
        (function(){
          try {
            var meta = document.querySelector('meta[name=viewport]');
            if (!meta) {
              meta = document.createElement('meta');
              meta.name = 'viewport';
              (document.head||document.documentElement).appendChild(meta);
            }
            meta.content = 'width=\(w), initial-scale=\(scale), minimum-scale=\(scale * 0.8), maximum-scale=3, user-scalable=yes';
            var id = 'veni-desktop-css';
            var st = document.getElementById(id);
            if (!st) {
              st = document.createElement('style');
              st.id = id;
              (document.head||document.documentElement).appendChild(st);
            }
            st.textContent = `
              html { background:#000!important; height:100%!important; }
              body { background:#000!important; min-width:\(w)px!important; min-height:\(h)px!important; margin:0!important; }
              #app-mount { min-height:\(h)px!important; }
            `;
            document.documentElement.style.background = '#000';
            if (document.body) document.body.style.background = '#000';
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

    func adjustScale(factor: CGFloat) {
        guard let wv = webView else { return }
        let js = """
        (function(){
          try {
            var m = document.querySelector('meta[name=viewport]');
            if (!m) return 'no-meta';
            var c = m.content || '';
            var scale = 0.35;
            var mm = c.match(/initial-scale=([0-9.]+)/);
            if (mm) scale = parseFloat(mm[1]);
            scale = Math.max(0.22, Math.min(0.7, scale * \(factor)));
            m.content = 'width=\(AppConfig.viewportWidth), initial-scale=' + scale + ', maximum-scale=3, user-scalable=yes';
            return 'scale=' + scale;
          } catch(e) { return String(e); }
        })();
        """
        wv.evaluateJavaScript(js) { [weak self] r, _ in
            self?.log("zoom \(String(describing: r ?? ""))")
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
        let chunkSize = 400_000
        var parts: [String] = []
        var idx = b64.startIndex
        while idx < b64.endIndex {
            let j = b64.index(idx, offsetBy: chunkSize, limitedBy: b64.endIndex) ?? b64.endIndex
            parts.append(String(b64[idx..<j]))
            idx = j
        }
        let partsJS = parts.map { "'\($0)'" }.joined(separator: ",")

        let loader = """
        (function(){
          if (!\(forceLit) && window.__veniVencordInjected && window.Vencord) return 'already';
          try {
            var old = document.getElementById('veni-vencord');
            if (old) old.remove();
            var code = atob([\(partsJS)].join(''));
            var el = document.createElement('script');
            el.id = 'veni-vencord';
            el.textContent = code;
            (document.documentElement || document.head || document.body).appendChild(el);
            window.__veniVencordInjected = true;
            return 'ok-script:' + code.length + ':vencord=' + (typeof window.Vencord);
          } catch(e) {
            try {
              var code = atob([\(partsJS)].join(''));
              (0, eval)(code);
              window.__veniVencordInjected = true;
              return 'ok-eval:vencord=' + (typeof window.Vencord);
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
                    self?.vencordStatus = "injected → \(r)"
                    self?.log("Vencord inject OK (#\(self?.injectCount ?? 0)) \(r)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.checkVencord()
                    }
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

        for delay in [0.4, 1.2, 3.0, 6.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let wv = self.webView else { return }
                self.applyDesktopLayout(into: wv)
                self.injectVencord(into: wv)
            }
        }
    }

    func handleJSMessage(_ body: Any) {
        let text: String
        if let s = body as? String { text = s }
        else if let d = body as? [String: Any] {
            text = (d["message"] as? String) ?? String(describing: d)
        } else {
            text = String(describing: body)
        }
        let lower = text.lowercased()
        if lower.hasPrefix("error") || text.contains("TypeError") || text.contains("ReferenceError") {
            logError(text)
        } else if lower.hasPrefix("warn") {
            log(String(text.prefix(200)))
        } else {
            log("js: \(text.prefix(250))")
        }
    }
}
