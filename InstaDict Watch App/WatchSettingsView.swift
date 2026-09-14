import SwiftUI

enum WatchSettingsAccess: String, CaseIterable, Identifiable {
    case swipe, button
    var id: String { rawValue }
    var title: String { self == .swipe ? "Swipe left" : "Lower-left button" }
}

struct WatchSettingsView: View {
    @AppStorage("watchSettingsAccess") private var access = WatchSettingsAccess.swipe
    @Environment(\.dismiss) private var dismiss
    @State private var showingTutorial = false

    var body: some View {
        NavigationStack {
            List {
                Section { InterfaceLanguagePicker() }
                Section { PronunciationOrderPicker() }
                NavigationLink {
                    WatchDictionariesView()
                } label: { Label("Manage dictionaries", systemImage: "books.vertical") }
                Section {
                    Picker("Open settings", selection: $access) {
                        ForEach(WatchSettingsAccess.allCases) { choice in
                            Text(LocalizedStringKey(choice.title)).tag(choice)
                        }
                    }
                } footer: {
                    Text("Choose how to open settings from a definition.")
                }
                Section {
                    Button("Show tutorial again", systemImage: "questionmark.circle") { showingTutorial = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingTutorial) { TutorialSheet() }
    }
}

struct WatchDictionariesView: View {
    @State private var downloads = DictionaryDownloads.shared
    @State private var sync = DictionarySync.shared

    var body: some View {
        List {
            Section {
                ForEach(downloads.packs) { pack in
                    NavigationLink {
                        WatchDictionaryDetailView(pack: pack)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(pack.id.title))
                            if downloads.verifying.contains(pack.id) {
                                Text("Verifying…").font(.caption2)
                            } else if let fraction = downloads.progress[pack.id] {
                                ProgressView(value: fraction)
                            } else {
                                Text(sync.local.installed.contains { $0.pack.hasSameContent(as: pack) }
                                     ? L10n.ui("Installed") : L10n.fileSize(pack.byteCount))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Download directly on your Watch. An internet connection is needed only for downloads.")
            }
            if let message = downloads.catalogMessage {
                Text(L10n.message(message)).font(.footnote).foregroundStyle(.secondary)
            }
            Button("Refresh catalog", systemImage: "arrow.clockwise") {
                Task { await downloads.refreshCatalog() }
            }
            .disabled(downloads.isRefreshing)
            NavigationLink("Download source") { WatchDownloadSourceView() }
        }
        .navigationTitle("Dictionaries")
        .task {
            downloads.start()
            await sync.refreshLocal()
            await downloads.refreshCatalog()
        }
    }
}

private struct WatchDictionaryDetailView: View {
    let pack: DictionaryPack
    @State private var downloads = DictionaryDownloads.shared
    @State private var sync = DictionarySync.shared
    @State private var confirmingRemoval = false
    @State private var removalError: String?
    @State private var removing = false

    private var installed: InstalledPack? { sync.local.installed.first { $0.pack.id == pack.id } }
    private var isCurrent: Bool { installed?.pack.hasSameContent(as: pack) == true }

    var body: some View {
        List {
            Section {
                Text(LocalizedStringKey(pack.id.subtitle)).font(.footnote)
                Text(L10n.ui("%@ entries · %@", L10n.number(pack.entryCount), L10n.fileSize(pack.byteCount)))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(pack.id.sourceSummary).font(.caption2).foregroundStyle(.secondary)
                if downloads.verifying.contains(pack.id) || sync.busy.contains(pack.id) {
                    ProgressView("Installing…")
                } else if let fraction = downloads.progress[pack.id] {
                    ProgressView(value: fraction) { Text(L10n.ui("Downloading · %@%%", L10n.number(Int(fraction * 100)))) }
                    Button("Cancel download", role: .cancel) { downloads.cancel(pack.id) }
                } else if isCurrent {
                    Label("Installed on Watch", systemImage: "checkmark.circle")
                } else {
                    Button(LocalizedStringKey(installed == nil ? "Download" : "Download update"), systemImage: "arrow.down.circle") {
                        Task { await downloads.download(pack) }
                    }
                    .disabled(downloads.isRefreshing || downloads.isRestoring || removing)
                }
                if let error = downloads.errors[pack.id] ?? removalError {
                    Text(L10n.message(error)).font(.footnote).foregroundStyle(.red)
                }
            }
            if installed != nil {
                Button("Remove from Watch", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
                    .disabled(downloads.verifying.contains(pack.id) || sync.busy.contains(pack.id) || removing)
            }
        }
        .navigationTitle(LocalizedStringKey(pack.id.title))
        .confirmationDialog(L10n.ui("Remove %@ from this Watch?", L10n.ui(pack.id.title)), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) {}
            Button("Remove dictionary", role: .destructive) {
                downloads.cancel(pack.id)
                removing = true
                Task {
                    defer { removing = false }
                    do {
                        _ = try await DictionaryLibrary.shared.beginLocalChange(pack.id, pack: nil)
                        await sync.refreshLocal()
                    } catch { removalError = L10n.errorMessage(error) }
                }
            }
        } message: { Text("You can download it again later. The iPhone copy is kept.") }
    }
}

private struct WatchDownloadSourceView: View {
    @State private var downloads = DictionaryDownloads.shared
    @State private var address = ""
    @State private var message: String?

    var body: some View {
        List {
            Text(downloads.sourceDisplayName).font(.caption2).foregroundStyle(.secondary)
            TextField("example.com/dictionaries", text: $address)
                .accessibilityLabel("Source address")
            Button("Check & save") { apply(address) }
                .disabled(!downloads.canChangeSource)
            Button("Use default source") { apply(DictionaryCatalog.remoteURL.absoluteString) }
                .disabled(!downloads.canChangeSource)
            if downloads.isRefreshing { ProgressView("Checking…") }
            if let message { Text(L10n.message(message)).font(.footnote) }
        }
        .navigationTitle("Download source")
        .onAppear { address = downloads.editableSourceAddress }
    }

    private func apply(_ input: String) {
        message = nil
        Task {
            do {
                try await downloads.changeSource(to: input)
                address = downloads.editableSourceAddress
                message = "Source saved."
            } catch { message = L10n.errorMessage(error) }
        }
    }
}
