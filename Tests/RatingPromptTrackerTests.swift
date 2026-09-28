import Foundation
import Testing
@testable import InstaDictCore

@Test @MainActor func ratingPromptTrackerUsesEachStageAndStopsAfterThird() throws {
    let name = "InstaDict.RatingPromptTrackerTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let tracker = RatingPromptTracker(defaults: defaults)
    let start = Date(timeIntervalSince1970: 2_000_000_000)

    tracker.becameActive(at: start)
    for _ in 0..<2 { tracker.enteredBackground(); tracker.becameActive(at: start) }
    for _ in 0..<5 { tracker.completedLookup() }
    #expect(!tracker.beginSettingsInvitation(at: start.addingTimeInterval(3 * 86_400 - 1)))
    #expect(tracker.beginSettingsInvitation(at: start.addingTimeInterval(3 * 86_400)))
    tracker.answer(.notNow)

    for _ in 0..<7 { tracker.enteredBackground(); tracker.becameActive(at: start) }
    for _ in 0..<5 { tracker.completedLookup() }
    #expect(tracker.beginSettingsInvitation(at: start.addingTimeInterval(7 * 86_400)))
    tracker.answer(.notNow)

    for _ in 0..<5 { tracker.enteredBackground(); tracker.becameActive(at: start) }
    for _ in 0..<20 { tracker.completedLookup() }
    #expect(!tracker.beginSettingsInvitation(at: start.addingTimeInterval(14 * 86_400 - 1)))
    #expect(tracker.beginSettingsInvitation(at: start.addingTimeInterval(14 * 86_400)))
    #expect(tracker.isTracking)
    tracker.answer(.notNow)
    #expect(!tracker.isTracking)
    #expect(!tracker.beginSettingsInvitation(at: .distantFuture))
}

@Test @MainActor func ratingPromptTrackerNeverAgainFinishesImmediately() throws {
    let name = "InstaDict.RatingPromptTrackerTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let tracker = RatingPromptTracker(defaults: defaults)
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    tracker.becameActive(at: start)
    for _ in 0..<2 { tracker.enteredBackground(); tracker.becameActive(at: start) }
    for _ in 0..<5 { tracker.completedLookup() }
    #expect(tracker.beginSettingsInvitation(at: start.addingTimeInterval(3 * 86_400)))
    tracker.answer(.neverAgain)
    #expect(!tracker.isTracking)
}
