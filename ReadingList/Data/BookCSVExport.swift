import Foundation
import ReadingList_Foundation

enum BookCsvColumn: CaseIterable {
    case isbn13
    case googleBooksId
    case title
    case subtitle
    case authors
    case pageCount
    case publicationDate
    case publisher
    case bookDescription
    case subjects
    case language
    case startedReading
    case finishedReading
    case currentPage
    case currentPercentage
    case rating
    case notes
}

extension BookCsvColumn: CsvColumn {
    static var dateFormat: String { "YYYY-MM-DD" }

    static var export: CsvExport<BookCsvColumn> {
        CsvExport(columns: BookCsvColumn.allCases)
    }

    var mandatoryForImport: Bool {
        return self == .title || self == .authors
    }

    var header: String {
        switch self {
        case .isbn13: return "ISBN-13"
        case .googleBooksId: return "Google Books ID"
        case .title: return "Title"
        case .subtitle: return "Subtitle"
        case .authors: return "Authors"
        case .pageCount: return "Page Count"
        case .publicationDate: return "Publication Date"
        case .publisher: return "Publisher"
        case .bookDescription: return "Description"
        case .subjects: return "Subjects"
        case .language: return "Language Code"
        case .startedReading: return "Started Reading"
        case .finishedReading: return "Finished Reading"
        case .currentPage: return "Current Page"
        case .currentPercentage: return "Current Percentage"
        case .rating: return "Rating"
        case .notes: return "Notes"
        }
    }

    func cellValue(_ book: Book) -> String? { //swiftlint:disable:this cyclomatic_complexity
        switch self {
        case .isbn13: return book.isbn13?.string
        case .googleBooksId: return book.googleBooksId
        case .title: return book.title
        case .subtitle: return book.subtitle
        case .authors: return book.authors.map(\.lastNameCommaFirstName).joined(separator: "; ")
        case .pageCount: return book.pageCount?.string
        case .publicationDate: return book.publicationDate?.string(withDateFormat: Self.dateFormat)
        case .publisher: return book.publisher
        case .bookDescription: return book.bookDescription
        case .subjects: return book.subjects.map(\.name).joined(separator: "; ")
        case .language: return book.language?.rawValue
        case .startedReading: return book.startedReading?.string(withDateFormat: Self.dateFormat)
        case .finishedReading: return book.finishedReading?.string(withDateFormat: Self.dateFormat)
        case .notes: return book.notes
        case .currentPage:
            guard let currentPage = book.currentPage, book.progressAuthority == .page else { return nil }
            return currentPage.string
        case .currentPercentage:
            guard let currentPercentage = book.currentPercentage, book.progressAuthority == .percentage else { return nil }
            return currentPercentage.string
        case .rating:
            guard let rating = book.rating, let ratingDouble = Double(exactly: rating) else { return nil }
            return "\(ratingDouble / 2)"
        }
    }
}

/*
        columns.append(contentsOf: lists.map { listName in
            CsvColumn<Book>(header: listName) { book in
                guard let list = book.lists.first(where: { $0.name == listName }) else { return nil }
                if let listIndex = book.listItems.first(where: { $0.list == list })?.sort {
                    return String(describing: listIndex + 1) // we use 1-based indexes
                } else {
                    assertionFailure("Unexpected missing list index")
                    return nil
                }
            }
        })*/
