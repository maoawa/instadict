import SwiftUI

struct FeedbackButton: View {
    private var emailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "instadict@candyrect.com"
        components.queryItems = [URLQueryItem(name: "subject", value: L10n.ui("InstaDict Feedback"))]
        return components.url!
    }

    #if os(iOS)
    @Environment(\.openURL) private var openURL
    @State private var showingMailUnavailable = false
    #endif

    var body: some View {
        #if os(watchOS)
        // SwiftUI hands mailto links to the system Mail composer on Apple Watch.
        Link(destination: emailURL) {
            Label("Feedback", systemImage: "envelope")
        }
        #else
        Button("Feedback", systemImage: "envelope") {
            openURL(emailURL) { accepted in
                showingMailUnavailable = !accepted
            }
        }
        .alert("Couldn’t open Mail", isPresented: $showingMailUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Email instadict@candyrect.com from a device with Mail set up.")
        }
        #endif
    }
}
