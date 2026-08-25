import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()
    @State private var showConsole = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.17, green: 0.18, blue: 0.21).ignoresSafeArea()

            DiscordWebView(model: model)
                .ignoresSafeArea()

            if model.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text("Canary + Vencord…")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.17, green: 0.18, blue: 0.21).opacity(0.9))
            }

            Button {
                showConsole.toggle()
            } label: {
                Image(systemName: showConsole ? "xmark.circle.fill" : "terminal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .padding(.trailing, 14)
            .padding(.bottom, 28)

            if showConsole {
                ConsolePanel(model: model) { showConsole = false }
                    .padding(.bottom, 70)
                    .padding(.horizontal, 10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showConsole)
    }
}

struct ConsolePanel: View {
    @ObservedObject var model: WebModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Clear") { model.clearLogs() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.cyan)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Color.white.opacity(0.15))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: model.logs.count) { _ in
                    if let last = model.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider().background(Color.white.opacity(0.15))

            HStack(spacing: 8) {
                Button("Re-inject Vencord") { model.forceReinject() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.9))
                    .cornerRadius(6)

                Button("Reload") { model.reload() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(6)

                Spacer()
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func color(for line: String) -> Color {
        let l = line.lowercased()
        if l.contains("error") || l.contains("fail") { return .red.opacity(0.9) }
        if l.contains("ok") || l.contains("inject") || l.contains("loaded") { return .green.opacity(0.9) }
        return .white.opacity(0.85)
    }
}
