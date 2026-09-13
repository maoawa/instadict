import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedIntroduction") private var hasCompletedIntroduction = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = LookupModel()
    @State private var sync = DictionarySync.shared
    @State private var input = WordInputPresenter()
    @State private var hasStarted = false
    @State private var shouldPromptOnActivation = false
    @State private var inputRequest: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if hasCompletedIntroduction {
                    if sync.local.installed.isEmpty {
                        DictionarySetupView(isInstalling: !sync.busy.isEmpty)
                    } else {
                        lookupContent
                    }
                } else {
                    IntroductionView {
                        hasCompletedIntroduction = true
                        requestInput()
                    }
                }
            }
            .containerBackground(.black, for: .navigation)
            .toolbar {
                if hasCompletedIntroduction, !sync.local.installed.isEmpty, model.canSwitchLanguage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.switchLanguage()
                        } label: {
                            Text(model.language == .english ? "中" : "EN")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        .tint(.accentColor)
                        .accessibilityLabel(model.language == .english ? "Look up in English–Chinese" : "Show English definitions")
                        .accessibilityIdentifier("dictionaryLanguage")
                    }
                }
            }
        }
        .task {
            sync.start()
            await sync.refreshLocal()
            guard !hasStarted else { return }
            hasStarted = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--reset-introduction") {
                hasCompletedIntroduction = false
            }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-word"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                hasCompletedIntroduction = true
                model.lookUp(ProcessInfo.processInfo.arguments[index + 1])
                if ProcessInfo.processInfo.arguments.contains("--preview-chinese") {
                    model.switchLanguage()
                }
                return
            }
            #endif
            if hasCompletedIntroduction { requestInput() }
        }
        .task(id: inputRequest) {
            guard inputRequest != nil else { return }
            await input.present { model.lookUp($0) }
        }
        .onChange(of: sync.local.installed) { previous, current in
            model.reloadCurrent()
            if previous.isEmpty, !current.isEmpty, hasCompletedIntroduction { requestInput() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                shouldPromptOnActivation = true
            } else if phase == .active, shouldPromptOnActivation {
                shouldPromptOnActivation = false
                if hasCompletedIntroduction { requestInput() }
            }
        }
    }

    @ViewBuilder
    private var lookupContent: some View {
        switch model.state {
        case .definition(let entry, let query):
            DefinitionView(entry: entry, query: query, language: model.language,
                           onLookup: model.lookUp, onNewWord: requestInput)
                .id(entry.id + model.language.rawValue)
        case .awaitingInput:
            LookupMessageView(
                symbol: "character.cursor.ibeam", title: "Look up a word",
                message: input.presentationFailed ? "Text entry couldn’t open. Tap below to try again." : "Your dictionary is ready. Enter a word to begin.",
                action: requestInput
            )
        case .loading(let query):
            VStack(spacing: 12) {
                ProgressView()
                Text(query).font(.headline).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notFound(let query, let suggestions):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title2).foregroundStyle(.tint)
                    Text("No entry for “\(query)”")
                        .font(.headline).accessibilityIdentifier("notFound")
                    Text("Check the spelling or try the base form of the word.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !suggestions.isEmpty {
                        Text("DID YOU MEAN?")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(suggestions, id: \.self) { word in
                            Button(word) { model.lookUp(word) }
                                .accessibilityLabel("Look up \(word)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 64)
            }
            .overlay(alignment: .bottomTrailing) {
                NewWordButton(action: requestInput)
                    .padding(.bottom, 8)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        case .needsPack(let id):
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "iphone.and.arrow.forward").font(.title2).foregroundStyle(.tint)
                    Text(id.title).font(.headline)
                    Text("Download and send this dictionary from InstaDict on your iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Enter another word", systemImage: "square.and.pencil", action: requestInput)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
            }
        case .failed(let message):
            LookupMessageView(symbol: "exclamationmark.book.closed", title: "Couldn’t look up word",
                              message: message, action: requestInput)
        }
    }

    private func requestInput() {
        guard !input.isPresenting, !sync.local.installed.isEmpty else { return }
        inputRequest = UUID()
    }
}

private struct LookupMessageView: View {
    let symbol: String
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.tint)
                Text(title).font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Enter a word", systemImage: "square.and.pencil", action: action)
                    .tint(.accentColor)
                    .accessibilityIdentifier("enterWord")
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
        }
    }
}

#Preview {
    ContentView()
}

private struct DictionarySetupView: View {
    let isInstalling: Bool
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward").font(.title2).foregroundStyle(.tint)
                Text(isInstalling ? "Installing dictionary…" : "One quick setup")
                    .font(.headline)
                if isInstalling { ProgressView() }
                Text("Open InstaDict on your iPhone. Choose a dictionary, then download and send it here.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("After that, just open and type. Your words work offline.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
        }
    }
}
