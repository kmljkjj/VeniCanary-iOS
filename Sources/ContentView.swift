import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()
    @State private var showConsole = false
    @State private var jsInput = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.17, green: 0.18, blue: 0.21).ignoresSafeArea()

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
                .background(Color(red: 0.17, green: 0.18, blue: 0.21).opacity(0.92))
            }

            Button {
                showConsole.toggle()
            } label: {
                Image(systemName: showConsole ? "xmark.circle.fill" : "terminal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(11)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.trailing, 12)
            .padding(.bottom, 36)

            if showConsole {
                consolePanel
                    .padding(.bottom, 78)
                    .padding(.horizontal, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showConsole)
    }

    private var consoleBag: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Console")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Clear") { model.clearLogs() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.cyan)
                    Button { showConsole = false } label: {
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
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.12))

            // Action buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    consoleBtn("Re-inject", color: .cyan) { model.forceReinject() }
                    consoleBtn("Check VC", color: .green) { model.checkVencord() }
                    consoleBtn("Reload", color: .orange) { model.reload() }
                    consoleBtn("Canary", color: .purple) { model.goCanary() }
                    consoleBtn("Layout", color: .mint) {
                        if let wv = model.webView { model.applyDesktopLayout(into: wv) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Divider().background(Color.white.opacity(0.12))

            // Logs
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(logColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.logs.count) { _ in
                    if let last = model.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(height: 160)

            Divider().background(Color.white.opacity(0.12))

            // JS eval like DevTools
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
                    guard !code.isEmpty else { return }
                    model.evalJS(code)
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
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func consoleBtn(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
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
        if l.contains("error") || l.contains("fail") { return .red.opacity(0.95) }
        if l.contains("ok") || l.contains("inject") || l.contains("loaded") { return .green.opacity(0.9) }
        if l.hasPrefix("[") && l.contains("] >") { return .cyan.opacity(0.9) }
        return .white.opacity(0.82)
    }
}
