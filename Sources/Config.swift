import Foundation
import UIKit

enum AppConfig {
    /// Canary desktop web (not mobile site)
    static let canaryURL = URL(string: "https://canary.discord.com/app")!

    static let vencordURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!,
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!,
    ]

    /// Discord desktop / Electron style UA → client “PC”, pas mobile web
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9164 Chrome/128.0.6613.186 Electron/32.2.2 Safari/537.36"

    /// Scale viewport for iPhone screens (14 Plus ~428pt wide)
    static var viewportScale: CGFloat {
        let w = UIScreen.main.bounds.width
        // Desktop Discord is designed ~1000–1280px; fit into phone width
        let targetDesktopWidth: CGFloat = 1180
        let scale = min(1.0, max(0.32, w / targetDesktopWidth))
        return scale
    }
}
