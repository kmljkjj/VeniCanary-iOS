import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            Color(red: 0.17, green: 0.18, blue: 0.21).ignoresSafeArea()

            DiscordWebView(model: model)
                .ignoresSafeArea()

            if model.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                    Text("Canary + Vencord…")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.17, green: 0.18, blue: 0.21).opacity(0.92))
            }
        }
    }
}
