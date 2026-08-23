# VeniCanary iOS

Client Discord **Canary** pour iPhone, dans l’esprit de **Vendroid** (Android) :

- ouvre **https://canary.discord.com** dans une **WKWebView**
- injecte **Vencord** (`browser.js`)
- build GitHub Actions → **IPA non signée**

> Ce n’est **pas** l’app Discord App Store. C’est un shell web + Vencord, comme Vendroid.

## Installation (iPhone)

1. Actions → workflow **Build IPA** → artifact `VeniCanary.ipa`
   ou Releases si un tag est poussé
2. Installe avec **SideStore**, **AltStore**, **TrollStore**, etc.
3. Tu signes avec **ton** Apple ID (l’IPA du CI n’est pas signée)

## Build local (Mac + Xcode)

```bash
brew install xcodegen
xcodegen generate
open VeniCanary.xcodeproj
# Product → Archive, ou:
xcodebuild -scheme VeniCanary -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/VeniCanary.xcarchive archive
```

## Réglages

| URL Discord | `https://canary.discord.com/login` |
|-------------|-------------------------------------|
| Vencord     | `https://github.com/Vendicated/Vencord/releases/download/devbuild/browser.js` |

Tu peux changer l’URL dans `Sources/Config.swift`.

## Limites (comme Vendroid)

- pas de VoIP / caméra natifs fiables
- notifications iOS limitées (WebView)
- dépend du site mobile/desktop web Discord

## Licence

MIT — Vencord reste sous sa propre licence (GPL).
