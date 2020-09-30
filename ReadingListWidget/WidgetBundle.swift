import SwiftUI
import WidgetKit

struct BooksEntry: TimelineEntry {
    let date: Date
    let books: [SharedBookData]
}

@main
struct ReadingListWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingListCurrentBooksWidget()
        ReadingListFinishedBooksWidget()
    }
}

struct ReadingListWidget_Previews: PreviewProvider {
    static let currentBooks = Bundle.main.decodedData(
        as: [SharedBookData].self,
        jsonFileName: "shared_current-books"
    )
    static let finishedBooks = Bundle.main.decodedData(
        as: [SharedBookData].self,
        jsonFileName: "shared_finished-books"
    )

    static var currentBooksEntry = BooksEntry(date: Date(), books: currentBooks)
    static var finishedBooksEntry = BooksEntry(date: Date(), books: finishedBooks)

    static var previews: some View {
        Group {
            ReadingListBooksView(books: currentBooksEntry.books, type: .current, entryDate: currentBooksEntry.date)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ReadingListBooksView(books: currentBooksEntry.books, type: .current, entryDate: currentBooksEntry.date)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ReadingListBooksView(books: currentBooksEntry.books, type: .current, entryDate: currentBooksEntry.date)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
            ReadingListBooksView(books: finishedBooksEntry.books, type: .finished, entryDate: finishedBooksEntry.date)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ReadingListBooksView(books: finishedBooksEntry.books, type: .finished, entryDate: finishedBooksEntry.date)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ReadingListBooksView(books: finishedBooksEntry.books, type: .finished, entryDate: finishedBooksEntry.date)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }.background(Color(.secondarySystemBackground))
    }
}
