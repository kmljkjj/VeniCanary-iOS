import Foundation
import WebKit
import Combine

final class WebModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var logs: [String] = []

    private(set) var vencordJS: String = ""
    weak var webView: WKWebView?
    private let maxLogs = 200

    override init() {
        super.init()
        log("VeniCanary start — Canary")
        Task { await preloadVencord() }
    }

    func log(_ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
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
        logs.removeAll()
        log("console cleared")
    }

    @MainActor
    func attach(_ webView: WKWebView) {
        self.webView = webView
        log("WebView attached → load Canary")
        var req = URLRequest(url: AppConfig.canaryURL)
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
        log("Force re-inject…")
        wv.evaluateJavaScript("window.__veniVencordInjected = false") { [weak self] _, _ in
            self?.injectVencord(into: wv, force: true)
        }
    }

    func preloadVencord() async {
        for url in AppConfig.vencordURLs {
            do {
                log("Fetch Vencord \(url.host ?? "")…")
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 30
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let s = String(data: data, encoding: .utf8), s.count > 500, (code == 200 || code == 0) {
                    await MainActor.run {
                        self.vencordJS = s
                        self.log("Vencord loaded OK (\(s.count) chars)")
                    }
                    return
                }
                log("bad response code=\(code) size=\(data.count)")
            } catch {
                log("fetch fail: \(error.localizedDescription)")
            }
        }
        log("ERROR could not load Vencord")
    }

    func injectVencord(into webView: WKWebView, force: Bool = false) {
        if vencordJS.isEmpty {
            log("Vencord empty — retry")
            Task {
                await preloadVencord()
                await MainActor.run { self.injectVencord(into: webView, force: force) }
            }
            return
        }

        let forceLit = force ? "true" : "false"
        let wrapped = """
        (function(){
          if (!\(forceLit) && window.__veniVencordInjected) return 'already';
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
            if r.contains("already") { self?.log("Vencord already injected") }
            else if r.contains("error") { self?.log("inject JS \(r)") }
            else { self?.log("Vencord inject OK") }
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
