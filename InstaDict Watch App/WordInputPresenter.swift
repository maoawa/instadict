import Observation
import WatchKit

@MainActor @Observable
final class WordInputPresenter {
    private(set) var isPresenting = false
    private(set) var presentationFailed = false

    func present(onSubmit: @escaping @MainActor (String) -> Void) async {
        guard !isPresenting else { return }
        isPresenting = true
        presentationFailed = false

        // SwiftUI's hosting controller may not yet exist on the first launch frame.
        for _ in 0..<30 {
            guard !Task.isCancelled else {
                isPresenting = false
                return
            }
            if WKApplication.shared().applicationState == .active,
               let controller = WKApplication.shared().visibleInterfaceController {
                controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { [weak self] results in
                    Task { @MainActor in
                        self?.isPresenting = false
                        if let word = results?.first as? String { onSubmit(word) }
                    }
                }
                return
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { break }
        }
        isPresenting = false
        presentationFailed = !Task.isCancelled
    }
}
