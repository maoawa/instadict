import SwiftUI
import WidgetKit

private struct LauncherEntry: TimelineEntry {
    let date: Date
}

private struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        // A launcher has no changing data and needs no scheduled background refresh.
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

private struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "character.book.closed")
                        .font(.title2)
                        .widgetAccentable()
                }
                .accessibilityLabel("Open InstaDict")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("InstaDict", systemImage: "character.book.closed")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Look up a word").font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "instadict://lookup")!)
    }
}

struct InstaDictLauncher: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InstaDictLauncher", provider: LauncherProvider()) { _ in
            LauncherView()
        }
        .configurationDisplayName("Open InstaDict")
        .description("Open InstaDict to look up a word.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct InstaDictWidgets: WidgetBundle {
    var body: some Widget { InstaDictLauncher() }
}

#Preview(as: .accessoryCircular) {
    InstaDictLauncher()
} timeline: {
    LauncherEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
    InstaDictLauncher()
} timeline: {
    LauncherEntry(date: .now)
}
