import SwiftUI
import UIKit

@main
struct InstaDictApp: App {
    @State private var languageSettings = LanguageSettings.shared
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            PhoneLookupView()
                .environment(\.locale, languageSettings.language.locale)
                .environment(DictionaryDownloads.shared)
                .environment(DictionarySync.shared)
                .tint(Color(uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.69, green: 0.886, blue: 0.702, alpha: 1)
                        : UIColor(red: 0.15, green: 0.40, blue: 0.27, alpha: 1)
                }))
                .task {
                    DictionarySync.shared.start()
                    DictionaryDownloads.shared.start()
                }
        }
    }
}

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // A WatchConnectivity wake-up need not create a SwiftUI view.
        DictionarySync.shared.start()
        DictionaryDownloads.shared.start()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DictionaryDownloads.sessionIdentifier else { completionHandler(); return }
        DictionarySync.shared.start()
        DictionaryDownloads.shared.handleBackgroundEvents(completionHandler)
    }
}
