import Foundation
import UIKit

enum AppConfig {
    static let canaryURL = URL(string: "https://canary.discord.com/app")!

    static let vencordURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!,
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!,
    ]

    /// Discord desktop Electron UA
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9164 Chrome/128.0.6613.186 Electron/32.2.2 Safari/537.36"

    /// iPhone 14 Plus logical width ~428; desktop Discord ~1000–1200
    static var viewportScale: CGFloat {
        let w = UIScreen.main.bounds.width
        let target: CGFloat = 1050
        return min(0.55, max(0.38, w / target))
    }

    static var viewportWidth: Int { 1050 }
}
