import SwiftUI

struct PhoneLookupView: View {
    @Environment(DictionarySync.self) private var sync
    @Environment(DictionaryDownloads.self) private var downloads
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = LookupModel()
    @State private var preferences = LookupPreferences.shared
    @AppStorage("hasCompletedIntroduction") private var hasCompletedIntroduction = false
    @State private var showingIntroduction = false
    @State private var word = ""
    @State private var showingSettings = false
    @State private var shouldPromptOnActivation = false
    @State private var promptAfterSettings = false
    @State private var searchPresented = false
    @State private var hasStarted = false

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .navigationTitle("InstaDict")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") {
                            searchPresented = false
                            showingSettings = true
                        }
                        .instaDictCircleButton()
                    }
                    if preferences.showsLanguageSwitch, model.canSwitchLanguage {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(LocalizedStringKey(model.language == .english ? "中" : "EN")) {
                                searchPresented = false
                                model.switchLanguage()
                            }
                            .instaDictCircleButton()
                            .accessibilityLabel(LocalizedStringKey(model.language == .english ? "Look up in English–Chinese" : "Show English definitions"))
                        }
                    }
                    if #available(iOS 26.0, *) {
                        DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    }
                }
        }
        .searchable(text: $word, isPresented: $searchPresented, prompt: "Enter a word")
        .searchDictationBehavior(.inline(activation: .onSelect))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search, search)
        .sheet(isPresented: $showingSettings, onDismiss: {
            if promptAfterSettings, hasCompletedIntroduction {
                promptAfterSettings = false
                searchPresented = true
            }
        }) { PhoneSettingsView() }
        .fullScreenCover(isPresented: $showingIntroduction, onDismiss: {
            if hasCompletedIntroduction { searchPresented = true }
        }) {
            NavigationStack {
                IntroductionView(onBegin: {
                    hasCompletedIntroduction = true
                    showingIntroduction = false
                })
            }
            .interactiveDismissDisabled()
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            // Focus as the first screen appears; library loading must not delay
            // text entry. A missing dictionary is explained after submission.
            await Task.yield()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--reset-introduction") {
                hasCompletedIntroduction = false
            }
            if ProcessInfo.processInfo.arguments.contains("--preview-settings") {
                showingSettings = true
                return
            }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-word"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                sync.start()
                downloads.start()
                await sync.refreshLocal()
                lookUp(ProcessInfo.processInfo.arguments[index + 1])
                return
            }
            #endif
            showingIntroduction = !hasCompletedIntroduction
            searchPresented = hasCompletedIntroduction
            sync.start()
            downloads.start()
            await sync.refreshLocal()
        }
        .onChange(of: sync.local.installed) { _, _ in model.reloadCurrent() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { LanguageSettings.shared.refreshDeviceLanguage() }
            if phase == .background {
                shouldPromptOnActivation = true
                searchPresented = false
            } else if phase == .active, shouldPromptOnActivation {
                shouldPromptOnActivation = false
                if showingSettings {
                    promptAfterSettings = true
                    showingSettings = false
                } else if hasCompletedIntroduction, !showingIntroduction { searchPresented = true }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .definition(let entry, let query):
            DefinitionView(entry: entry, query: query, language: model.language,
                           onLookup: lookUp)
                .id(entry.id + model.language.rawValue)
        case .awaitingInput:
            message("A word away.", symbol: "character.book.closed", detail: "Enter an English or Chinese word. Your downloaded dictionaries work offline.")
        case .loading(let query):
            ProgressView("Looking up \(query)…")
        case .notFound(let query, let suggestions):
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("No entry for “\(query)”").font(.title2.weight(.semibold))
                    Text("Check the spelling or try the base form.").foregroundStyle(.secondary)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { lookUp(suggestion) }.buttonStyle(.bordered)
                    }
                    Button("Enter another word", systemImage: "square.and.pencil", action: newWord)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        case .needsPack(let id):
            VStack(spacing: 18) {
                Image(systemName: "arrow.down.circle").font(.largeTitle).foregroundStyle(.tint)
                Text(L10n.ui("Download %@", L10n.ui(id.title))).font(.title2.weight(.semibold))
                Text("Add this dictionary in Settings to look up words on your iPhone.")
                    .foregroundStyle(.secondary)
                Button("Manage dictionaries", systemImage: "books.vertical") {
                    searchPresented = false
                    showingSettings = true
                }.buttonStyle(.borderedProminent)
            }.multilineTextAlignment(.center).padding(24)
        case .failed(let detail):
            message("Couldn’t look up word", symbol: "exclamationmark.book.closed", detail: detail)
        }
    }

    private func message(_ title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint)
            Text(LocalizedStringKey(title)).font(.system(.title, design: .serif, weight: .bold))
            Text(L10n.message(detail)).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).padding(24)
    }

    private func search() {
        guard !LookupQuery.normalize(word).isEmpty else { return }
        lookUp(word)
    }

    private func lookUp(_ input: String) {
        word = input
        searchPresented = false
        model.lookUp(input)
    }

    private func newWord() {
        word = ""
        searchPresented = true
    }
}

private struct PhoneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingTutorial = false

    var body: some View {
        NavigationStack {
            Form {
                Section { PronunciationOrderPicker() }
                Section { LookupPreferencesPicker() }
                NavigationLink {
                    DictionaryManagerView()
                } label: { Label("Manage dictionaries", systemImage: "books.vertical") }
                Section { InterfaceLanguagePicker() }
                Section { FeedbackButton() }
                Section {
                    Button("Show tutorial again", systemImage: "questionmark.circle") { showingTutorial = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingTutorial) { TutorialSheet() }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--preview-tutorial") { showingTutorial = true }
        }
        #endif
    }
}
