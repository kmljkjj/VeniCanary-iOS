import Foundation

enum Config {
    /// Discord Canary web client
    static let discordURL = URL(string: "https://canary.discord.com/login")!

    /// Vencord browser build (updated on Vencord devbuild releases)
    static let vencordBrowserJS =
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!

    static let vencordBrowserCSS =
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.css")!

    /// Fallback mirror
    static let vencordBrowserJSMirror =
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!

    static let appName = "VeniCanary"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
