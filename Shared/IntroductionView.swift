import SwiftUI

struct IntroductionView: View {
    @State private var page = 0
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("watchSettingsAccess") private var settingsAccess = "button"
    let onBegin: () -> Void
    var isReplay = false

    var body: some View {
        Group {
            #if os(iOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    phoneSection("Download dictionaries", symbol: "books.vertical",
                                 detail: "Open Settings, then Manage dictionaries. Download once and look up words offline.")
                    phoneSection("Look up a word", symbol: "magnifyingglass", detail: lookupTip)
                    phoneSection("Make it yours", symbol: "gearshape", detail: settingsTip, isLast: true)
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
                .multilineTextAlignment(.leading)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onBegin) {
                    Text(LocalizedStringKey(isReplay ? "Done" : "Look up a word now"))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
                .accessibilityIdentifier("beginLookup")
            }
            #else
            TabView(selection: $page) {
                tutorialPage("Download dictionaries", symbol: "books.vertical",
                             detail: "Open Settings, then Manage dictionaries. Download once and look up words offline.")
                    .tag(0)
                tutorialPage("Look up a word", symbol: "magnifyingglass", detail: lookupTip)
                    .tag(1)
                tutorialPage("Make it yours", symbol: "gearshape", detail: settingsTip, isLast: true)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(LocalizedStringKey(isReplay ? "Tutorial" : welcomeTitle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if isReplay {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: onBegin)
                        .instaDictCircleButton()
                }
            }
        }
        .accessibilityIdentifier("introduction")
    }

    private func tutorialPage(_ title: String, symbol: String, detail: String, isLast: Bool = false) -> some View {
        ScrollView {
            VStack(spacing: pageSpacing) {
                Image(systemName: symbol)
                    .font(symbolFont)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(title)).font(titleFont)
                Text(LocalizedStringKey(detail)).font(detailFont).foregroundStyle(.secondary)
                if isLast {
                    Text("Choose your default English dictionary in Settings. You can also hide the 中 / EN dictionary switch there.")
                        .font(detailFont).foregroundStyle(.secondary)
                } else {
                    Label("Swipe left for next", systemImage: "arrow.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                #if os(watchOS)
                if isLast {
                    Button(action: onBegin) {
                        Text(LocalizedStringKey(isReplay ? "Done" : "Look up a word"))
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("beginLookup")
                    .padding(.top, 8)
                }
                #endif
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.top, 8)
            // Leave room for the system page indicator on small Watch displays.
            .padding(.bottom)
        }
    }

    private var pageSpacing: CGFloat {
        #if os(watchOS)
        8
        #else
        16
        #endif
    }
    private var symbolFont: Font {
        #if os(watchOS)
        .title3
        #else
        .largeTitle
        #endif
    }
    private var titleFont: Font {
        #if os(watchOS)
        .headline
        #else
        .title2.bold()
        #endif
    }
    private var detailFont: Font {
        #if os(watchOS)
        .footnote
        #else
        .body
        #endif
    }

    private var lookupTip: String {
        #if os(iOS)
        "Open InstaDict and start typing. Use the search field to type or dictate your next word."
        #else
        "Open InstaDict and start typing. Tap the pencil on a definition to look up another word."
        #endif
    }

    private var settingsTip: String {
        #if os(iOS)
        "Open Settings with the upper-left button to choose your app language and pronunciation order."
        #else
        settingsAccess == "button"
            ? "Open Settings with the upper-left button. You can hide this button in Settings."
            : "Swipe left on a definition to open Settings. To show a button instead, choose Upper-left button in Settings."
        #endif
    }

    private var welcomeTitle: String {
        #if os(iOS)
        "Welcome to InstaDict"
        #else
        "Welcome"
        #endif
    }

    #if os(iOS)
    private func phoneSection(_ title: String, symbol: String, detail: String, isLast: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.title3.bold())
                .foregroundStyle(.tint)
            Text(LocalizedStringKey(detail))
                .foregroundStyle(.secondary)
            if isLast {
                Text("Choose your default English dictionary in Settings. You can also hide the 中 / EN dictionary switch there.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

}

struct TutorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            IntroductionView(onBegin: { dismiss() }, isReplay: true)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
