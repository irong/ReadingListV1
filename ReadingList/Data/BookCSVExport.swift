import Foundation
import ReadingList_Foundation

class BookCSVExport {
    static func build(withLists lists: [String]) -> CsvExport<Book> {
        var columns = [
            CsvColumn<Book>(header: "ISBN-13") { $0.isbn13?.string },
            CsvColumn<Book>(header: "Google Books ID") { $0.googleBooksId },
            CsvColumn<Book>(header: "Title") { $0.title },
            CsvColumn<Book>(header: "Subtitle") { $0.subtitle },
            CsvColumn<Book>(header: "Authors") { $0.authors.map { $0.lastNameCommaFirstName }.joined(separator: "; ") },
            CsvColumn<Book>(header: "Page Count") { $0.pageCount == nil ? nil : String(describing: $0.pageCount!) },
            CsvColumn<Book>(header: "Publication Date") { $0.publicationDate?.string(withDateFormat: "yyyy-MM-dd") },
            CsvColumn<Book>(header: "Publisher") { $0.publisher },
            CsvColumn<Book>(header: "Description") { $0.bookDescription },
            CsvColumn<Book>(header: "Subjects") { $0.subjects.map { $0.name }.joined(separator: "; ") },
            CsvColumn<Book>(header: "Language Code") { $0.language?.rawValue },
            CsvColumn<Book>(header: "Started Reading") { $0.startedReading?.string(withDateFormat: "yyyy-MM-dd") },
            CsvColumn<Book>(header: "Finished Reading") { $0.finishedReading?.string(withDateFormat: "yyyy-MM-dd") },
            CsvColumn<Book>(header: "Current Page") {
                if let currentPage = $0.currentPage, $0.progressAuthority == .page {
                    return String(describing: currentPage)
                } else {
                    return nil
                }
            },
            CsvColumn<Book>(header: "Current Percentage") {
                if let currentPercentage = $0.currentPercentage, $0.progressAuthority == .percentage {
                    return String(describing: currentPercentage)
                } else {
                    return nil
                }
            },
            CsvColumn<Book>(header: "Rating") { $0.rating == nil ? nil : String(describing: $0.rating!) },
            CsvColumn<Book>(header: "Notes") { $0.notes }
        ]

        columns.append(contentsOf: lists.map { listName in
            CsvColumn<Book>(header: listName) { book in
                guard let list = book.lists.first(where: { $0.name == listName }) else { return nil }
                return String(describing: list.books.index(of: book) + 1) // we use 1-based indexes
            }
        })

        return CsvExport<Book>(columns: columns)
    }

    static var headers: [String] {
        return build(withLists: []).columns.map { $0.header }
    }
}
