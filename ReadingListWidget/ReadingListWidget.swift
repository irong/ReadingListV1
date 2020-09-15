import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), books: SharedBookData.sharedBooks)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), books: SharedBookData.sharedBooks)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(date: entryDate, books: SharedBookData.sharedBooks)
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let books: [SharedBookData]
}

struct ReadingListWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        HStack {
            if entry.books.isEmpty {
                Text("No books")
            } else {
                ForEach(entry.books) { _ in
                    BookView()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
            }
        }
    }
}

struct BookView: View {
    var body: some View {
        VStack {
            Text("Catcher in the Rye")
            Text("J. D. Salinger")
        }.border(Color.black, width: 1)
    }
}

@main
struct ReadingListWidget: Widget {
    let kind: String = "ReadingListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ReadingListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
        .supportedFamilies([.systemMedium])
    }
}

struct ReadingListWidget_Previews: PreviewProvider {
    static var previews: some View {
        ReadingListWidgetEntryView(entry: SimpleEntry(date: Date(), books: []))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
