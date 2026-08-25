import Foundation
import UIKit

enum AppConfig {
    static let canaryURL = URL(string: "https://canary.discord.com/app")!

    static let vencordURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/Vencord/builds/main/browser.js")!,
        URL(string: "https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js")!,
    ]

    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9164 Chrome/128.0.6613.186 Electron/32.2.2 Safari/537.36"

    /// Largeur "virtuelle" desktop Discord
    static let layoutWidth: CGFloat = 1280
    /// Hauteur mini utile pour voir top bar + user panel
    static let layoutHeight: CGFloat = 800

    /// Scale pour que TOUT tienne dans l’écran (bandes noires OK)
    static var viewportScale: CGFloat {
        let bounds = UIScreen.main.bounds
        // safe area un peu réservée pour encoche / home indicator
        let safeW = bounds.width - 8
        let safeH = bounds.height - 28
        let scaleW = safeW / layoutWidth
        let scaleH = safeH / layoutHeight
        // min = tout visible, un peu de marge (0.95)
        let s = min(scaleW, scaleH) * 0.92
        return min(0.50, max(0.28, s))
    }

    static var viewportWidth: Int { Int(layoutWidth) }
}
