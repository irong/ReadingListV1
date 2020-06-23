import Foundation
import ReadingList_Foundation

enum ImportCsvFormat: Int, Codable, CaseIterable {
    case readingList = 0
    case goodreads = 1
}

extension ImportCsvFormat: CustomStringConvertible {
    var description: String {
        switch self {
        case .readingList:
            return "Reading List"
        case .goodreads:
            return "Goodreads"
        }
    }
}

struct ImportSettings: Codable {
    var downloadCoverImages = true
    var downloadMetadata = false
    var overwriteExistingBooks = false
}

protocol CsvRow {
    var values: [String: String] { get }
    var title: String { get }
    var authors: [Author] { get }
    var subtitle: String? { get }
    var description: String? { get }
    var started: Date? { get }
    var finished: Date? { get }
    var googleBooksId: String? { get }
    var manualBookId: String? { get }
    var isbn13: ISBN13? { get }
    var language: String? { get }
    var notes: String? { get }
    var currentPage: Int32? { get }
    var currentPercentage: Int32? { get }
    var pageCount: Int32? { get }
    var publicationDate: Date? { get }
    var publisher: String? { get }
    var rating: Double? { get }
    var subjects: [String] { get }
}

struct NativeCsvRow: CsvRow {
    static let requiredHeaders = ["Title", "Authors"]
    init?(_ values: [String: String]) {
        self.values = values

        guard let title = values[BookCsvColumn.title.header], let authors = values[BookCsvColumn.authors.header] else { return nil }
        self.title = title
        self.authors = authors.components(separatedBy: ";").compactMap {
            guard let authorString = $0.trimming().nilIfWhitespace() else { return nil }
            if let firstCommaPos = authorString.range(of: ","), let lastName = authorString[..<firstCommaPos.lowerBound].trimming().nilIfWhitespace() {
                return Author(lastName: lastName, firstNames: authorString[firstCommaPos.upperBound...].trimming().nilIfWhitespace())
            } else {
                return Author(lastName: authorString, firstNames: nil)
            }
        }
        guard !self.authors.isEmpty else { return nil }
    }

    let values: [String: String]
    func value(_ csvColumn: BookCsvColumn) -> String? {
        values[csvColumn.header]
    }

    let title: String
    let authors: [Author]
    var subtitle: String? { value(.subtitle) }
    var description: String? { value(.bookDescription) }
    var started: Date? { Date(value(.startedReading), format: "yyyy-MM-dd") }
    var finished: Date? { Date(value(.finishedReading), format: "yyyy-MM-dd") }
    var googleBooksId: String? { value(.googleBooksId) }
    var manualBookId: String? { values["Reading List ID"] }
    var isbn13: ISBN13? { ISBN13(value(.isbn13)) }
    var language: String? { value(.language) }
    var notes: String? { value(.notes) }
    var currentPage: Int32? { Int32(value(.currentPage)) }
    var currentPercentage: Int32? { Int32(value(.currentPercentage)) }
    var pageCount: Int32? { Int32(value(.pageCount)) }
    var publicationDate: Date? { Date(value(.publicationDate), format: "yyyy-MM-dd") }
    var publisher: String? { value(.publisher) }
    var rating: Double? {
        guard let ratingString = value(.rating), let ratingValue = Double(ratingString) else { return nil }
        return ratingValue
    }
    var subjects: [String] { value(.subjects)?.components(separatedBy: ";").compactMap { $0.trimming().nilIfWhitespace() } ?? [] }
}

struct CsvGoodReadsRow: CsvRow {
    static let requiredHeaders = ["Title", "Author l-f"]

    init?(_ values: [String: String]) {
        guard let title = values["Title"], let author = values["Author l-f"] else { return nil }
        self.title = title

        let firstAuthor: Author
        if let firstCommaPos = author.range(of: ","), let lastName = author[..<firstCommaPos.lowerBound].trimming().nilIfWhitespace() {
            firstAuthor = Author(lastName: lastName, firstNames: author[firstCommaPos.upperBound...].trimming().nilIfWhitespace())
        } else {
            firstAuthor = Author(lastName: author, firstNames: nil)
        }

        var additionalAuthors = [Author]()
        if let additionalAuthorsCell = values["Additional Authors"] {
            for additionalAuthor in additionalAuthorsCell.components(separatedBy: ",") {
                guard let trimmedAuthor = additionalAuthor.trimming().nilIfWhitespace() else { continue }
                if let range = trimmedAuthor.range(of: " ", options: .backwards),
                    let lastName = trimmedAuthor[range.upperBound...].trimming().nilIfWhitespace() {
                    additionalAuthors.append(Author(lastName: lastName, firstNames: trimmedAuthor[..<range.upperBound].trimming().nilIfWhitespace()))
                } else {
                    additionalAuthors.append(Author(lastName: trimmedAuthor, firstNames: nil))
                }
            }
        }
        self.authors = [firstAuthor] + additionalAuthors

        self.values = values
        self.bookshelves = values["Bookshelves"]?.split(separator: ",").compactMap { $0.trimming().nilIfWhitespace() } ?? []
    }

    let values: [String: String]
    let title: String
    let authors: [Author]
    let bookshelves: [String]

    var description: String? { nil }
    var subtitle: String? { nil }
    var started: Date? {
        guard bookshelves.contains("read") || bookshelves.contains("currently-reading") else { return nil }
        if let dateString = values["Date Read"] ?? values["Date Added"] {
            return Date(dateString, format: "yyyy/MM/dd")
        } else {
             return Date()
        }
    }
    var finished: Date? {
        guard bookshelves.contains("read") else { return nil }
        if let dateString = values["Date Read"] ?? values["Date Added"] {
            return Date(dateString, format: "yyyy/MM/dd")
        } else {
            return Date()
        }
    }
    var googleBooksId: String? { nil }
    var manualBookId: String? { values["Book Id"] }
    var isbn13: ISBN13? {
        // The GoodReads export seems to present ISBN's like: ="9781231231231"
        ISBN13(values["ISBN13"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"=")))
    }
    var language: String? { nil }
    var notes: String? { values["My Review"] }
    var currentPage: Int32? { nil }
    var currentPercentage: Int32? { nil }
    var pageCount: Int32? { Int32(values["Number of Pages"]) }
    var publicationDate: Date? { nil }
    var publisher: String? { values["Publisher"] }
    var rating: Double? {
        guard let ratingString = values["My Rating"], let ratingValue = Double(ratingString) else { return nil }
        return ratingValue
    }
    var subjects: [String] { [] }
}
