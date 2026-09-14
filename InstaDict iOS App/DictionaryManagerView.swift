import SwiftUI

struct DictionaryManagerView: View {
    @Environment(DictionaryDownloads.self) private var downloads
    @Environment(DictionarySync.self) private var sync
    @Environment(\.scenePhase) private var phase

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: 34)).foregroundStyle(.tint)
                        Text("A word away.")
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                        Text("Download dictionaries for offline lookup on this iPhone. You can also send them to your Apple Watch.")
                            .font(.body).foregroundStyle(.secondary)
                        Label(L10n.message(sync.connectionMessage), systemImage: "applewatch")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let message = sync.watchStatusMessage {
                            Text(L10n.message(message)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    if let message = downloads.catalogMessage {
                        Label(L10n.message(message), systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(downloads.packs) { pack in
                        DictionaryCard(pack: pack)
                    }
                    Text("Downloads stay on your iPhone until you remove them. Your Watch keeps its own copy, so your phone can stay behind.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dictionaries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh catalog", systemImage: "arrow.clockwise") {
                        Task { await downloads.refreshCatalog() }
                    }
                    .disabled(downloads.isRefreshing)
                }
            }
            .refreshable {
                sync.checkWatchStatus()
                await downloads.refreshCatalog()
            }
            .onChange(of: phase) { _, value in
                if value == .active {
                    sync.checkWatchStatus()
                    Task { await sync.refreshLocal() }
                }
            }
    }
}

private struct DictionaryCard: View {
    let pack: DictionaryPack
    @Environment(DictionaryDownloads.self) private var downloads
    @Environment(DictionarySync.self) private var sync
    @State private var confirmingRemoval = false
    @Environment(\.colorScheme) private var colorScheme

    private var installed: InstalledPack? { sync.local.installed.first { $0.pack.id == pack.id } }
    private var isCurrent: Bool { installed?.pack.hasSameContent(as: pack) == true }
    private var isOnWatch: Bool { sync.watch.installed.contains { $0.pack.hasSameContent(as: pack) } }
    private var inProgress: Bool { downloads.progress[pack.id] != nil || downloads.verifying.contains(pack.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringKey(pack.id.title)).font(.title3.weight(.semibold))
                    Text(LocalizedStringKey(pack.id.subtitle)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    if let installed {
                        if sync.watch.installed.contains(where: { $0.pack.id == pack.id }) {
                            Button("Send to Watch again", systemImage: "arrow.up.applewatch") {
                                Task { await sync.send(installed.pack) }
                            }
                            .disabled(sync.transfers[pack.id] != nil)
                        }
                        Button("Remove from iPhone", systemImage: "iphone.slash", role: .destructive) {
                            Task { await sync.removeFromPhone(pack.id) }
                        }
                    }
                    Button("Remove from Watch", systemImage: "applewatch.slash", role: .destructive) {
                        sync.removeFromWatch(pack.id)
                    }
                    Button("Remove from both", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .disabled(inProgress || sync.busy.contains(pack.id))
                .accessibilityLabel(L10n.ui("Manage %@", L10n.ui(pack.id.title)))
            }
            Text(L10n.ui("%@ entries · %@", L10n.number(pack.entryCount), L10n.fileSize(pack.byteCount)))
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label(LocalizedStringKey(installed == nil ? "Not downloaded" : isCurrent ? "Downloaded on iPhone" : "Update available"), systemImage: "iphone")
                Label(L10n.message(sync.status(for: pack.id)), systemImage: "applewatch")
            }
            .font(.footnote).foregroundStyle(.secondary)
            if sync.hasPendingCommand(pack.id) {
                Button(LocalizedStringKey(sync.isCheckingWatch ? "Checking Watch…" : "Check Watch status"), systemImage: "arrow.clockwise") {
                    sync.checkWatchStatus()
                }
                .font(.footnote)
                .disabled(sync.isCheckingWatch)
                Text("Open InstaDict on your Watch to check its installed dictionaries. File transfers can continue in the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink {
                DictionarySourcesView(id: pack.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictionary sources").italic()
                    Text(pack.id.sourceSummary).font(.caption2).foregroundStyle(Color.secondary)
                }
            }
            .font(.footnote)
            if let error = downloads.errors[pack.id] {
                Text(L10n.message(error)).font(.footnote).foregroundStyle(.red)
            }
            if let progress = downloads.progress[pack.id] {
                ProgressView(value: progress) {
                    HStack {
                        Text(L10n.ui("Downloading · %@%%", L10n.number(Int(progress * 100))))
                        Spacer()
                        Button("Cancel") { downloads.cancel(pack.id) }
                    }.font(.footnote)
                }
            } else if downloads.verifying.contains(pack.id) {
                ProgressView("Verifying dictionary…").font(.footnote)
            } else if !isCurrent || !isOnWatch {
                Button {
                    if isCurrent, let installed { Task { await sync.send(installed.pack) } }
                    else { Task { await downloads.download(pack) } }
                } label: {
                    Label(LocalizedStringKey(isCurrent ? "Send to Watch" : installed == nil ? "Download on iPhone" : "Download update"),
                          systemImage: isCurrent ? "arrow.up.applewatch" : "arrow.down.circle")
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloads.isRefreshing || downloads.isRestoring || sync.busy.contains(pack.id) || sync.transfers[pack.id] != nil)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .confirmationDialog(L10n.ui("Remove %@ from both devices?", L10n.ui(pack.id.title)), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) {}
            Button("Remove from both", role: .destructive) {
                sync.removeFromWatch(pack.id)
                Task { await sync.removeFromPhone(pack.id) }
            }
        } message: { Text("You can download it again later. Watch removal will finish when it reconnects.") }
    }
}

struct DictionaryDownloadSourceView: View {
    @Environment(DictionaryDownloads.self) private var downloads
    @State private var address = ""
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Text(downloads.sourceDisplayName)
                    .font(.footnote).textSelection(.enabled)
            } header: { Text("Current source") }
            Section {
                TextField("example.com/dictionaries", text: $address, axis: .vertical)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Source address")
                Button("Check & save") { apply(address) }
                    .disabled(!downloads.canChangeSource || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use default source") { apply(DictionaryCatalog.remoteURL.absoluteString) }
                    .disabled(!downloads.canChangeSource)
            } header: { Text("Catalog address") } footer: {
                Text("Enter a website and folder, such as example.com/dictionaries. HTTPS and manifest.json are added automatically. The source is checked before saving. Installed dictionaries stay available offline.")
            }
            if downloads.isRefreshing {
                ProgressView("Checking catalog…")
            } else if !downloads.canChangeSource {
                Text("Wait for downloads to finish before changing the source.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message {
                Text(L10n.message(message)).font(.footnote).foregroundStyle(failed ? Color.red : Color.secondary)
            }
        }
        .navigationTitle("Download source")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { address = downloads.editableSourceAddress }
    }

    private func apply(_ input: String) {
        message = nil
        Task {
            do {
                try await downloads.changeSource(to: input)
                address = downloads.editableSourceAddress
                failed = false
                message = "Source saved."
            } catch {
                failed = true
                message = L10n.errorMessage(error)
            }
        }
    }
}

private struct DictionarySourcesView: View {
    let id: DictionaryID
    private var notices: String {
        guard let url = Bundle.main.url(forResource: id.rawValue + "-licenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Source notices couldn’t be loaded." }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey(id.title)).font(.title2.bold())
                Text(id.sourceSummary).font(.headline)
                Text(L10n.message(notices)).font(.footnote).textSelection(.enabled)
            }.padding(20).frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle("Dictionary sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
