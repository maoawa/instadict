import Foundation

/// Local, per-device counters used only to schedule the three Settings invitations.
/// No query text or event history is retained. Finishing deletes the counters.
@MainActor
final class RatingPromptTracker {
    static let shared = RatingPromptTracker()
    static let storageKey = "ratingInvitation.v1"

    enum Answer { case yes, notNow, neverAgain }

    private struct Usage: Codable {
        var firstUse: Date
        var opens = 0
        var lookups = 0
        var prompts = 0
        var firstPrompt: Date?
        var pendingPrompt: Int?
    }

    private struct State: Codable {
        var finished = false
        var usage: Usage?
    }

    private let defaults: UserDefaults
    private var state: State
    private var isInForeground = false
    var isTracking: Bool { !state.finished }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    func becameActive(at now: Date = .now) {
        guard isTracking, !isInForeground else { return }
        isInForeground = true
        // First foreground use is a conservative lower bound on installation age.
        // Existing installs start here too: earlier usage cannot be reconstructed.
        var usage = state.usage ?? Usage(firstUse: now)
        usage.opens = min(usage.opens + 1, 15)
        state.usage = usage
        save()
    }

    func enteredBackground() {
        isInForeground = false
    }

    /// Called once for a completed, user-initiated search (including no results).
    /// Language switches, reloads, canceled searches and errors don't count.
    func completedLookup() {
        guard isTracking, var usage = state.usage else { return }
        usage.lookups = min(usage.lookups + 1, 30)
        state.usage = usage
        save()
    }

    /// Call only on a new Settings presentation, never when a lookup completes.
    /// Mark the invitation pending before displaying it so an interruption repeats
    /// the same stage instead of silently consuming a chance.
    func beginSettingsInvitation(at now: Date = .now) -> Bool {
        guard isTracking, var usage = state.usage else { return false }
        let requirements = [(days: 3, opens: 3, lookups: 5, wait: 0),
                            (days: 7, opens: 10, lookups: 10, wait: 3),
                            (days: 14, opens: 15, lookups: 30, wait: 5)]
        guard requirements.indices.contains(usage.prompts) else { return false }
        if usage.pendingPrompt == usage.prompts { return true }
        let rule = requirements[usage.prompts]
        let day: TimeInterval = 24 * 60 * 60
        guard now.timeIntervalSince(usage.firstUse) >= Double(rule.days) * day,
              usage.opens >= rule.opens, usage.lookups >= rule.lookups else { return false }
        if rule.wait > 0 {
            guard let firstPrompt = usage.firstPrompt,
                  now.timeIntervalSince(firstPrompt) >= Double(rule.wait) * day else { return false }
        }
        usage.pendingPrompt = usage.prompts
        if usage.firstPrompt == nil { usage.firstPrompt = now }
        state.usage = usage
        save()
        return true
    }

    func answer(_ answer: Answer) {
        switch answer {
        case .yes, .neverAgain: finish()
        case .notNow:
            guard isTracking, var usage = state.usage,
                  usage.pendingPrompt == usage.prompts else { return }
            usage.prompts += 1
            usage.pendingPrompt = nil
            state.usage = usage
            if usage.prompts == 3 { finish() } else { save() }
        }
    }

    private func finish() {
        guard isTracking else { return }
        state = State(finished: true)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
