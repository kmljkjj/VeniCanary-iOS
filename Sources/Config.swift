import Foundation

enum AppConfig {
    static let canaryURL = URL(string: "https://canary.discord.com/login")!
    static let vencordURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!,
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!,
    ]
    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
