import Foundation

enum Config {
    /// Discord Canary desktop web client
    static let discordURL = URL(string: "https://canary.discord.com/login")!

    /// Official Vencord browser builds
    static let vencordBrowserJS = URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!
    static let vencordBrowserCSS = URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.css")!
    static let vencordBrowserJSMirror = URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!
    static let vencordBrowserCSSMirror = URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.css")!

    static let appName = "VeniCanary"

    /// Spoof Discord desktop Electron client so Discord serves full PC UI
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Discord/1.0.9166 Chrome/134.0.6998.205 Electron/35.3.0 Safari/537.36"
}
