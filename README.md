# VeniCanary-iOS

Équivalent **iOS (IPA)** de [Vencord/Vendroid](https://github.com/Vencord/Vendroid), mais sur **Discord Canary** (pas Stable).

## Principe (comme Vendroid)

1. Ouvre `https://canary.discord.com/app` dans un **WKWebView**
2. Injecte **Vencord** (`browser.js`)
3. Build **IPA** non signée via GitHub Actions

## Installer

1. Repo → **Actions** → **Build IPA** → Run workflow  
2. Télécharge l’artifact `VeniCanary.ipa`  
3. Signe / installe avec **TrollStore**, **AltStore**, **Sideloadly**, **Scarlet**, etc.

## Différences vs Vendroid Android

| | Vendroid | VeniCanary-iOS |
|--|----------|----------------|
| Plateforme | Android APK | iOS IPA |
| Discord | Stable `discord.com` | **Canary** `canary.discord.com` |
| Moteur | WebView | WKWebView |
| Mod | Vencord | Vencord |

## Limites (web client)

Comme Vendroid : pas de vraie app native Discord. Voix / notifs push limitées selon iOS et le site.

## Structure

```
Sources/
  App.swift
  ContentView.swift
  WebModel.swift
project.yml          # XcodeGen
.github/workflows/build-ipa.yml
```
