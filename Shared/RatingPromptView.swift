import SwiftUI
import StoreKit

extension View {
    func trackRatingUsage() -> some View {
        modifier(RatingUsageModifier())
    }

    func ratingInvitation() -> some View {
        modifier(RatingInvitationModifier())
    }

    #if os(iOS)
    func companionReviewReceiver() -> some View {
        modifier(CompanionReviewReceiverModifier())
    }
    #endif
}

private struct RatingUsageModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: RatingPromptTracker.shared.becameActive()
            case .background: RatingPromptTracker.shared.enteredBackground()
            default: break // Dictation, system alerts and wrist-down aren't new opens.
            }
        }
    }
}

private struct RatingInvitationModifier: ViewModifier {
    #if os(iOS)
    @Environment(\.requestReview) private var requestReview
    @State private var reviewAfterDismissal = false
    #endif
    @State private var checkedThisVisit = false
    @State private var showingInvitation = false
    @State private var isManualPreview = false
    #if os(iOS)
    @State private var invitationWasAnswered = false
    @State private var selectedDetent: PresentationDetent = .medium
    #endif

    private var isPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-rating-prompt")
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        let settings = content.onAppear {
            guard !checkedThisVisit else { return }
            checkedThisVisit = true
            #if os(iOS)
            selectedDetent = .medium
            invitationWasAnswered = false
            #endif
            showingInvitation = isPreview || RatingPromptTracker.shared.beginSettingsInvitation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .instadictManualRatingPrompt)) { _ in
            isManualPreview = true
            #if os(iOS)
            selectedDetent = .medium
            invitationWasAnswered = false
            #endif
            showingInvitation = true
        }
        #if os(iOS)
        // Native alerts own their title alignment. A system sheet lets us center
        // this heading using public SwiftUI layout while retaining native controls.
        settings.sheet(isPresented: $showingInvitation, onDismiss: {
            if !invitationWasAnswered {
                answer(.notNow)
            }
            invitationWasAnswered = false
            if reviewAfterDismissal {
                reviewAfterDismissal = false
                submitNativeReviewRequest()
            }
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Enjoying InstaDict?\n(｡•ᴗ•｡)")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    invitationMessage
                        .foregroundStyle(.secondary)
                    if selectedDetent == .large {
                        Text("(づ｡◕‿‿◕｡)づ ⭐️ OMG, you found me! Can you feed me with a 5-star meal so I can stay motivated to make InstaDict even better?")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 12) {
                        invitationActions
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
        }
        #else
        settings.alert("Enjoying InstaDict?\n(｡•ᴗ•｡)", isPresented: $showingInvitation) {
            invitationActions
        } message: {
            invitationMessage
        }
        #endif
    }

    private var invitationMessage: Text {
        Text("If InstaDict has been a little help, would you kindly spare a moment to rate it? Your support means so much and keeps us going. Thank you! ❤️")
    }

    @ViewBuilder private var invitationActions: some View {
        Button {
            answer(.yes)
            #if os(iOS)
            invitationWasAnswered = true
            reviewAfterDismissal = true
            #else
            DictionarySync.shared.requestCompanionReview()
            #endif
            showingInvitation = false
        } label: {
            Text("Yes, I’d love to! ❤️").frame(maxWidth: .infinity)
        }
        Button {
            answer(.notNow)
            #if os(iOS)
            invitationWasAnswered = true
            #endif
            showingInvitation = false
        } label: {
            Text("Not now ⏰").frame(maxWidth: .infinity)
        }
        Button {
            answer(.neverAgain)
            #if os(iOS)
            invitationWasAnswered = true
            #endif
            showingInvitation = false
        } label: {
            Text("Don’t show this again").frame(maxWidth: .infinity)
        }
    }

    private func answer(_ choice: RatingPromptTracker.Answer) {
        // Preview actions must not opt the real installation out of invitations.
        if !isPreview && !isManualPreview { RatingPromptTracker.shared.answer(choice) }
        isManualPreview = false
    }

    #if os(iOS)
    private func submitNativeReviewRequest() {
        RatingPromptSupport.markNativeReviewRequest()
        requestReview()
    }
    #endif
}

#if os(iOS)
private struct CompanionReviewReceiverModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var pendingRequest = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .instadictCompanionReviewRequest)) { _ in
                pendingRequest = true
                submitIfActive()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                if UserDefaults.standard.bool(forKey: RatingPromptSupport.pendingCompanionReviewKey) {
                    pendingRequest = true
                }
                submitIfActive()
            }
    }

    private func submitIfActive() {
        guard scenePhase == .active, pendingRequest else { return }
        pendingRequest = false
        UserDefaults.standard.set(false, forKey: RatingPromptSupport.pendingCompanionReviewKey)
        RatingPromptSupport.markNativeReviewRequest()
        requestReview()
    }
}
#endif

struct TestFlightRatingPromptButton: View {
    var body: some View {
        if TestFlightSupport.canTestRatingPrompt {
            Section {
                Button("Rate us", systemImage: "star.bubble") {
                    NotificationCenter.default.post(name: .instadictManualRatingPrompt, object: nil)
                }
            }
        }
    }
}
