import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Only mount WebView once Vencord is downloaded (so injection is present at first load)
            if model.ready {
                DiscordWebView(model: model)
            }

            if model.isLoading || !model.ready {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                        .scaleEffect(1.3)
                    Text("VeniCanary")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.black.opacity(0.85))
                .cornerRadius(16)
            }
        }
        .onAppear { model.start() }
    }
}
