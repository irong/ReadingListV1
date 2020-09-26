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

struct ReadingListCurrentBooksWidget: Widget {
    let kind: String = "com.andrewbennet.books.current-books"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookTimelineProvider()) { entry in
            ReadingListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Books")
        .description("Quick access to the books are you reading or are next in your To Read list.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ReadingListSingleBookWidget: Widget {
    let kind: String = "com.andrewbennet.books.single-book"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookTimelineProvider()) { entry in
            SingleBookOrAddBook(book: entry.books.first)
        }
        .configurationDisplayName("Current Book")
        .description("Quick access to the book at the top of your reading list")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ReadingListWidgetBundle: WidgetBundle {
    let kind: String = "com.andrewbennet.books.current-books"

    var body: some Widget {
        ReadingListCurrentBooksWidget()
    }
}

struct ReadingListWidget_Previews: PreviewProvider {
    static let data: [SharedBookData] = {
        let dataPath = Bundle.main.url(forResource: "shared_book_data", withExtension: "json")!
        return try! JSONDecoder().decode([SharedBookData].self, from: Data(contentsOf: dataPath))
    }()

    static var previews: some View {
        Group {
            SingleBookOrAddBook(book: nil)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SingleBookOrAddBook(book: data.first)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ReadingListWidgetEntryView(entry: BooksEntry(date: Date(), books: data))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ReadingListWidgetEntryView(entry: BooksEntry(date: Date(), books: data))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
