import Foundation
import Combine

@MainActor
final class WebModel: ObservableObject {
    @Published var isLoading = true
    @Published var statusText = "Chargement Canary…"
    @Published var vencordScript: String?
    @Published var vencordCSS: String?

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task { await loadVencord() }
    }

    private func loadVencord() async {
        statusText = "Téléchargement Vencord…"
        do {
            let (jsData, _) = try await URLSession.shared.data(from: Config.vencordBrowserJS)
            if let js = String(data: jsData, encoding: .utf8), js.count > 1000 {
                vencordScript = js
            } else {
                let (js2, _) = try await URLSession.shared.data(from: Config.vencordBrowserJSMirror)
                vencordScript = String(data: js2, encoding: .utf8)
            }

            if let (cssData, _) = try? await URLSession.shared.data(from: Config.vencordBrowserCSS),
               let css = String(data: cssData, encoding: .utf8) {
                vencordCSS = css
            }

            statusText = "Ouverture de Discord Canary…"
            isLoading = false
        } catch {
            // Still open Discord even if Vencord fails
            statusText = "Vencord indisponible — Canary seul"
            isLoading = false
        }
    }
}
