import SwiftUI

struct DictionaryManagerView: View {
    @Environment(DictionaryDownloads.self) private var downloads
    @Environment(DictionarySync.self) private var sync
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: 34)).foregroundStyle(.tint)
                        Text("A word away.")
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                        Text("Choose your dictionaries. Download once, then look up words offline on your Apple Watch.")
                            .font(.body).foregroundStyle(.secondary)
                        Label(sync.connectionMessage, systemImage: "applewatch")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if let message = downloads.catalogMessage {
                        Label(message, systemImage: "info.circle")
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
            .refreshable { await downloads.refreshCatalog() }
            .onChange(of: phase) { _, value in
                if value == .active { Task { await sync.refreshLocal() } }
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
    private var isCurrent: Bool { installed?.pack == pack }
    private var inProgress: Bool { downloads.progress[pack.id] != nil || downloads.verifying.contains(pack.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(pack.id.title).font(.title3.weight(.semibold))
                    Text(pack.id.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    if installed != nil {
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
                .accessibilityLabel("Manage \(pack.id.title)")
            }
            Text("\(pack.entryCount.formatted()) entries · \(ByteCountFormatter.string(fromByteCount: pack.byteCount, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label(installed == nil ? "Not downloaded" : isCurrent ? "Downloaded on iPhone" : "Update available", systemImage: "iphone")
                Label(sync.status(for: pack.id), systemImage: "applewatch")
            }
            .font(.footnote).foregroundStyle(.secondary)
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
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let progress = downloads.progress[pack.id] {
                ProgressView(value: progress) {
                    HStack {
                        Text("Downloading · \(Int(progress * 100))%")
                        Spacer()
                        Button("Cancel") { downloads.cancel(pack.id) }
                    }.font(.footnote)
                }
            } else if downloads.verifying.contains(pack.id) {
                ProgressView("Verifying dictionary…").font(.footnote)
            } else {
                Button {
                    if isCurrent { Task { await sync.send(pack) } }
                    else { downloads.download(pack) }
                } label: {
                    Label(isCurrent ? "Send to Watch" : installed == nil ? "Download & send" : "Download update",
                          systemImage: isCurrent ? "arrow.up.applewatch" : "arrow.down.circle")
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sync.busy.contains(pack.id) || sync.transfers[pack.id] != nil)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .confirmationDialog("Remove \(pack.id.title) from both devices?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove from both", role: .destructive) {
                sync.removeFromWatch(pack.id)
                Task { await sync.removeFromPhone(pack.id) }
            }
        } message: { Text("You can download it again later. Watch removal will finish when it reconnects.") }
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
                Text(id.title).font(.title2.bold())
                Text(id.sourceSummary).font(.headline)
                Text(notices).font(.footnote).textSelection(.enabled)
            }.padding(20).frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle("Dictionary sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
