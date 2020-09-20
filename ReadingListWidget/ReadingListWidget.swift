import WidgetKit
import SwiftUI

struct BookTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BooksEntry {
        BooksEntry(date: Date(), books: SharedBookData.sharedBooks)
    }

    func getSnapshot(in context: Context, completion: @escaping (BooksEntry) -> Void) {
        completion(BooksEntry(date: Date(), books: SharedBookData.sharedBooks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The "timeline" consists of one entry, now, which never expires. The app itself is in charge of invaliding the
        // widget when stuff changes.
        let entries = [BooksEntry(date: Date(), books: SharedBookData.sharedBooks)]
        let timeline = Timeline(entries: entries, policy: .never)
        completion(timeline)
    }
}

struct BooksEntry: TimelineEntry {
    let date: Date
    let books: [SharedBookData]
}

struct ReadingListWidgetEntryView: View {
    var entry: BookTimelineProvider.Entry

    var body: some View {
        if entry.books.isEmpty {
            NoBooksDisplay()
        } else {
            CurrentBooks(books: entry.books)
        }
    }
}

@main
struct ReadingListWidget: Widget {
    let kind: String = "com.andrewbennet.books.current-books"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookTimelineProvider()) { entry in
            ReadingListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Books")
        .description("Quick access to the books are you reading or are next in your To Read list.")
        .supportedFamilies([.systemMedium])
    }
}
