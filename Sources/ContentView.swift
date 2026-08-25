import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()
    @State private var showConsole = false
    @State private var jsInput = ""
    @State private var consoleTab = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Fond noir = bandes / letterbox
            Color.black.ignoresSafeArea()

            DiscordWebView(model: model)
                .ignoresSafeArea()

            if model.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    Text("Canary desktop + Vencord…")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.subheadline)
                    Text(model.vencordStatus)
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92))
            }

            Button(action: { showConsole.toggle() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: showConsole ? "xmark.circle.fill" : "terminal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .padding(11)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                    if !model.errors.isEmpty && !showConsole {
                        Text("\(min(model.errors.count, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.trailing, 12)
            .padding(.bottom, 36)

            if showConsole {
                ConsoleSheet(
                    model: model,
                    jsInput: $jsInput,
                    consoleTab: $consoleTab,
                    onClose: { showConsole = false }
                )
                .padding(.bottom, 78)
                .padding(.horizontal, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showConsole)
    }
}

struct ConsoleSheet: View {
    @ObservedObject var model: WebModel
    @Binding var jsInput: String
    @Binding var consoleTab: Int
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Console")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(consoleTab == 0 ? "Clear" : "Clear errors") {
                        if consoleTab == 0 { model.clearLogs() } else { model.clearErrors() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.cyan)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Text("URL: \(model.pageURL)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                Text("Vencord: \(model.vencordStatus) · injects: \(model.injectCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 0) {
                tabButton("Logs", index: 0, badge: nil)
                tabButton("Errors", index: 1, badge: model.errors.count)
            }
            .padding(.horizontal, 8)

            Divider().background(Color.white.opacity(0.12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Re-inject", .cyan) { model.forceReinject() }
                    chip("Check VC", .green) { model.checkVencord() }
                    chip("Reload", .orange) { model.reload() }
                    chip("Layout", .mint) {
                        if let wv = model.webView { model.applyDesktopLayout(into: wv) }
                    }
                    // Zoom manuel
                    chip("Zoom −", .gray) { model.adjustScale(factor: 0.85) }
                    chip("Zoom +", .gray) { model.adjustScale(factor: 1.15) }
                    if consoleTab == 1 {
                        chip("Copy errors", .red) {
                            UIPasteboard.general.string = model.exportErrorsText()
                            model.log("errors copied")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Divider().background(Color.white.opacity(0.12))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        let lines = consoleTab == 0 ? model.logs : model.errors
                        if lines.isEmpty {
                            Text(consoleTab == 0 ? "(pas de logs)" : "(aucune erreur)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(8)
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(consoleTab == 1 ? Color.red.opacity(0.95) : logColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.logs.count) { _ in
                    if consoleTab == 0, let last = model.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                .onChange(of: model.errors.count) { _ in
                    if consoleTab == 1, let last = model.errors.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(height: 140)

            Divider().background(Color.white.opacity(0.12))

            HStack(spacing: 6) {
                TextField("JS…", text: $jsInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                Button("Run") {
                    let code = jsInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !code.isEmpty { model.evalJS(code) }
                }
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.cyan)
                .cornerRadius(6)
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func tabButton(_ title: String, index: Int, badge: Int?) -> some View {
        Button { consoleTab = index } label: {
            HStack(spacing: 4) {
                Text(title).font(.caption.weight(.semibold))
                if let b = badge, b > 0 {
                    Text("\(b)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(consoleTab == index ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(consoleTab == index ? Color.white.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
    }

    private func chip(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.9))
                .cornerRadius(6)
        }
    }

    private func logColor(_ line: String) -> Color {
        let l = line.lowercased()
        if l.contains("error") || l.contains("fail") || l.hasPrefix("err ") { return .red.opacity(0.95) }
        if l.contains("ok") || l.contains("inject") || l.contains("loaded") { return .green.opacity(0.9) }
        return .white.opacity(0.82)
    }
}
