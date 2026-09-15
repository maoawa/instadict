import SwiftUI

struct FeedbackButton: View {
    @Environment(\.openURL) private var openURL
    @State private var showingMailUnavailable = false

    var body: some View {
        Button("Feedback", systemImage: "envelope") {
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = "instadict@candyrect.com"
            components.queryItems = [URLQueryItem(name: "subject", value: L10n.ui("InstaDict Feedback"))]
            guard let url = components.url else { return }
            #if os(watchOS)
            // watchOS exposes URL opening without a completion callback.
            openURL(url)
            #else
            openURL(url) { accepted in
                showingMailUnavailable = !accepted
            }
            #endif
        }
        .alert("Couldn’t open Mail", isPresented: $showingMailUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Email instadict@candyrect.com from a device with Mail set up.")
        }
    }
}
