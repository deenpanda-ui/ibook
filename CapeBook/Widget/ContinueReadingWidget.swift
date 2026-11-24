import WidgetKit
import SwiftUI

// Виджет для экрана блокировки: одно касание — и открывается книга на том месте, где вы остановились

struct ContinueEntry: TimelineEntry {
    let date: Date
}

struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry { ContinueEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) { completion(ContinueEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        completion(Timeline(entries: [ContinueEntry(date: Date())], policy: .never))
    }
}

struct ContinueView: View {
    @Environment(\.widgetFamily) var family
    var entry: ContinueEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "book.fill").font(.system(size: 22, weight: .semibold))
            }
            .widgetAccentable()
        case .accessoryInline:
            Label("Read", systemImage: "book.fill")
        default:
            HStack(spacing: 8) {
                Image(systemName: "book.fill").font(.title2).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("CapeBook").font(.headline).widgetAccentable()
                    Text("Read").font(.caption)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReading", provider: ContinueProvider()) { entry in
            ContinueView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "capebook://continue"))
        }
        .configurationDisplayName("Read")
        .description("Одно касание — и книга открыта на том месте, где вы остановились.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct CapeBookWidgets: WidgetBundle {
    var body: some Widget { ContinueReadingWidget() }
}
