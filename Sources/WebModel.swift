import Foundation
import Combine

@MainActor
final class WebModel: ObservableObject {
    @Published var isLoading = true
    @Published var statusText = "Préparation…"
    @Published var ready = false
    @Published var vencordScript: String?
    @Published var vencordCSS: String?
    @Published var vencordOK = false

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task { await prepare() }
    }

    private func prepare() async {
        statusText = "Téléchargement Vencord…"
        var js: String?
        var css: String?

        // Primary + mirror for JS
        for url in [Config.vencordBrowserJS, Config.vencordBrowserJSMirror] {
            if let text = await fetchText(url), text.count > 50_000 {
                js = text
                break
            }
        }

        for url in [Config.vencordBrowserCSS, Config.vencordBrowserCSSMirror] {
            if let text = await fetchText(url), text.count > 100 {
                css = text
                break
            }
        }

        vencordScript = js
        vencordCSS = css
        vencordOK = js != nil

        if vencordOK {
            statusText = "Vencord OK — ouverture Discord PC…"
        } else {
            statusText = "Vencord indisponible — Discord seul"
        }

        // Small delay so UI updates, then show WebView with scripts already in hand
        try? await Task.sleep(nanoseconds: 300_000_000)
        ready = true
        isLoading = false
    }

    private func fetchText(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 45
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
