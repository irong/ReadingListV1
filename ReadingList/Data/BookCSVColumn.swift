import Foundation
import ReadingList_Foundation

enum BookCSVColumn: CaseIterable {
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
    case lists
}

extension BookCSVColumn: CsvColumn {
    static var dateFormat: String { "YYYY-MM-dd" }

    static var export: CsvExport<BookCSVColumn> {
        CsvExport(columns: BookCSVColumn.allCases)
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
        case .lists: return "Lists"
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
        case .lists:
            // We want to return a cell value like:
            //      List A (19); List B (3); List C (4)
            // but each list name could contain a semi colon, or even be equal to the whole string above. To remove abiguity,
            // we escape the semicolons which appear in the list names to '\;', but in order to do that we also need to escape
            // the back slash to a double backslash ('\\') first.
            // Finally, increment the sort value to make them 1-based.
            return book.listItems.sorted(byAscending: { $0.list.name }).map {
                "\($0.list.name.replacingOccurrences(of: #"\"#, with: #"\\"#).replacingOccurrences(of: ";", with: #"\;"#)) (\($0.sort + 1))"
            }.joined(separator: "; ")
        }
    }
}
