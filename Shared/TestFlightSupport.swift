import Foundation
import OSLog

enum TestFlightSupport {
    /// Debug builds and TestFlight builds expose the manual prompt control.
    /// App Store builds have a production receipt and keep it hidden.
    static var canTestRatingPrompt: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

enum RatingPromptSupport {
    static let pendingCompanionReviewKey = "ratingPrompt.pendingCompanionReview.v1"
    static let lastNativeReviewRequestKey = "ratingPrompt.lastNativeReviewRequest.v1"
    private static let logger = Logger(subsystem: "com.candyrect.instadict", category: "RatingPrompt")

    static func markNativeReviewRequest() {
        UserDefaults.standard.set(Date(), forKey: lastNativeReviewRequestKey)
        logger.notice("Submitted StoreKit requestReview()")
    }
}

extension Notification.Name {
    static let instadictManualRatingPrompt = Notification.Name("instadict.manualRatingPrompt")
    static let instadictCompanionReviewRequest = Notification.Name("instadict.companionReviewRequest")
}
