import SwiftUI
import WidgetKit

struct ReadingListBooksView: View {
    @Environment(\.widgetFamily) var size: WidgetFamily
    var books: [SharedBookData]
    var entryDate: Date

    var body: some View {
        if books.isEmpty {
            NoBooksView()
        } else if size == .systemSmall {
            SingleBookView(book: books[0], entryDate: entryDate)
        } else {
            BookGrid(books: books)
        }
    }
}
