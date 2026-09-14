import SwiftUI

struct IntroductionView: View {
    #if os(iOS)
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 32
    @ScaledMetric(relativeTo: .body) private var textSize = 20
    @ScaledMetric(relativeTo: .body) private var tipSize = 18
    #else
    @ScaledMetric(relativeTo: .title3) private var titleSize = 20
    @ScaledMetric(relativeTo: .footnote) private var textSize = 13
    @ScaledMetric(relativeTo: .caption2) private var tipSize = 12
    #endif
    @AppStorage("watchSettingsAccess") private var settingsAccess = "swipe"
    @Environment(\.colorScheme) private var colorScheme
    let onBegin: () -> Void
    var isReplay = false

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "character.book.closed.fill")
                            .foregroundStyle(.tint)
                        Text("InstaDict")
                            .font(.system(size: titleSize, weight: .bold, design: .serif))
                    }
                    Text("Download dictionaries in Settings. Then open InstaDict and type to look up words offline.")
                        .font(.system(size: textSize)).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "square.and.pencil").frame(width: 22)
                        Text("Look up a new word")
                    }
                    .font(.system(size: tipSize))
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "gearshape").frame(width: 22)
                        #if os(iOS)
                        Text("Open Settings to manage dictionaries and preferences")
                        #else
                        Text(LocalizedStringKey(settingsAccess == "button" ? "Tap the lower-left button for settings" : "Swipe left on a definition for settings"))
                        #endif
                    }
                    .font(.system(size: tipSize))
                    HStack(alignment: .top, spacing: 10) {
                        Text("中").fontWeight(.semibold).frame(width: 22)
                        Text("English–Chinese")
                    }
                    .font(.system(size: tipSize))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
            .clipped()
            Button(LocalizedStringKey(isReplay ? "Done" : "Look up a word"), action: onBegin)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .accessibilityIdentifier("beginLookup")
        }
        .accessibilityIdentifier("introduction")
    }
}

struct TutorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            IntroductionView(onBegin: { dismiss() }, isReplay: true)
                .navigationTitle("Tutorial")
        }
    }
}
