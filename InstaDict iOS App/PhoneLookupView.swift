import SwiftUI

struct PhoneLookupView: View {
    @Environment(DictionarySync.self) private var sync
    @Environment(DictionaryDownloads.self) private var downloads
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = LookupModel()
    @State private var word = ""
    @State private var showingSettings = false
    @State private var shouldPromptOnActivation = false
    @State private var promptAfterSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Enter a word", text: $word)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($inputFocused)
                            .onSubmit(search)
                            .accessibilityIdentifier("wordInput")
                        if !word.isEmpty {
                            Button("Clear word", systemImage: "xmark.circle.fill") {
                                word = ""
                                inputFocused = true
                            }
                            .labelStyle(.iconOnly).foregroundStyle(.tint)
                        }
                        Button("Look up", systemImage: "arrow.right.circle.fill", action: search)
                            .labelStyle(.iconOnly)
                            .disabled(LookupQuery.normalize(word).isEmpty)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .background(Color(.systemBackground))
                }
                .navigationTitle("InstaDict")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") {
                            inputFocused = false
                            showingSettings = true
                        }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.accentColor)
                    }
                    if model.canSwitchLanguage {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(LocalizedStringKey(model.language == .english ? "中" : "EN")) {
                                inputFocused = false
                                model.switchLanguage()
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.accentColor)
                            .accessibilityLabel(LocalizedStringKey(model.language == .english ? "Look up in English–Chinese" : "Show English definitions"))
                        }
                    }
                    if !inputFocused, !model.lastQuery.isEmpty {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Spacer()
                            Button("Look up a new word", systemImage: "square.and.pencil", action: newWord)
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.accentColor)
                                .accessibilityIdentifier("newWord")
                        }
                    }
                }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if promptAfterSettings {
                promptAfterSettings = false
                inputFocused = true
            }
        }) { PhoneSettingsView() }
        .task {
            // Focus as the first screen appears; library loading must not delay
            // text entry. A missing dictionary is explained after submission.
            await Task.yield()
            #if DEBUG
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-word"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                sync.start()
                downloads.start()
                await sync.refreshLocal()
                lookUp(ProcessInfo.processInfo.arguments[index + 1])
                return
            }
            #endif
            inputFocused = true
            sync.start()
            downloads.start()
            await sync.refreshLocal()
        }
        .onChange(of: sync.local.installed) { _, _ in model.reloadCurrent() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                shouldPromptOnActivation = true
            } else if phase == .active, shouldPromptOnActivation {
                shouldPromptOnActivation = false
                if showingSettings {
                    promptAfterSettings = true
                    showingSettings = false
                } else { inputFocused = true }
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
                    inputFocused = false
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
        inputFocused = false
        model.lookUp(input)
    }

    private func newWord() {
        word = ""
        inputFocused = true
    }
}

private struct PhoneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingTutorial = false

    var body: some View {
        NavigationStack {
            Form {
                Section { InterfaceLanguagePicker() }
                Section { PronunciationOrderPicker() }
                NavigationLink {
                    DictionaryManagerView()
                } label: { Label("Manage dictionaries", systemImage: "books.vertical") }
                NavigationLink {
                    DictionaryDownloadSourceView()
                } label: { Label("Download source", systemImage: "network") }
                Section {
                    Text("Open InstaDict and start typing. Dictionaries downloaded on this iPhone are available offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
    }
}
