import Foundation

enum Config {
    /// Discord Canary — desktop web client (better full UI than mobile site)
    static let discordURL = URL(string: "https://canary.discord.com/login")!

    /// Vencord browser build
    static let vencordBrowserJS =
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!

    static let vencordBrowserCSS =
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.css")!

    static let vencordBrowserJSMirror =
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!

    static let appName = "VeniCanary"

    /// Desktop Chrome UA so Discord serves the PC layout (not the tiny mobile site)
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
}
