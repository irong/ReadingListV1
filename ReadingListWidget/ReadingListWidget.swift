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
        let startOfToday = Date().start
        // Let's get a week's worth of entries
        let entries = (0..<7).map { index in
            BooksEntry(date: startOfToday.addingDays(index), books: SharedBookData.sharedBooks)
        }
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct BooksEntry: TimelineEntry {
    let date: Date
    let books: [SharedBookData]
}

struct ReadingListCurrentBooksView: View {
    @Environment(\.widgetFamily) var size
    var entry: BookTimelineProvider.Entry

    var body: some View {
        if entry.books.isEmpty {
            NoBooksView()
        } else if size == .systemSmall {
            SingleBookView(book: entry.books[0], entryDate: entry.date)
        } else {
            BookGrid(books: entry.books)
        }
    }
}

struct ReadingListCurrentBooksWidget: Widget {
    let kind: String = "com.andrewbennet.books.current-books"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookTimelineProvider()) { entry in
            ReadingListCurrentBooksView(entry: entry)
        }
        .configurationDisplayName("Current Books")
        .description("Quick access to the books are you reading or are next in your To Read list.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ReadingListWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingListCurrentBooksWidget()
    }
}

struct ReadingListWidget_Previews: PreviewProvider {
    static let data: [SharedBookData] = {
        let dataPath = Bundle.main.url(forResource: "shared_book_data", withExtension: "json")!
        return try! JSONDecoder().decode([SharedBookData].self, from: Data(contentsOf: dataPath))
    }()

    static var entry = BooksEntry(date: Date(), books: data)

    static var previews: some View {
        Group {
            ReadingListCurrentBooksView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ReadingListCurrentBooksView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ReadingListCurrentBooksView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }.background(Color(.secondarySystemBackground))
    }
}
