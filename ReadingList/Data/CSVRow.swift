import Foundation
import Regex
import ReadingList_Foundation

struct ImportSettings: Codable {
    var downloadCoverImages = true
    var downloadMetadata = false
    var overwriteExistingBooks = false
}

struct CSVRow {
    let title: String
    let authors: [Author]
    let subtitle: String?
    let description: String?
    let started: Date?
    let finished: Date?
    let googleBooksId: String?
    let manualBookId: String?
    let isbn13: ISBN13?
    let language: String?
    let notes: String?
    let currentPage: Int32?
    let currentPercentage: Int32?
    let pageCount: Int32?
    let publicationDate: Date?
    let publisher: String?
    let rating: Double?
    let subjects: [String]
    let lists: [ListIndex]

    struct ListIndex {
        let listName: String
        let index: Int32
    }

    private static let extractListDetail = Regex(#"((.+?) \((\d+)\)(?:;|$))"#)

    init?(for format: ImportCSVFormat, row: [String: String]) {
        switch format {
        case .readingList:
            self.init(readingListRow: row)
        case .goodreads:
            self.init(goodreadsRow: row)
        }
    }

    init?(readingListRow row: [String: String]) {
        func value(_ csvColumn: BookCSVColumn) -> String? {
            row[csvColumn.header]
        }

        guard let title = value(.title), let authors = value(.authors) else { return nil }
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

        subtitle = value(.subtitle)
        description = value(.bookDescription)
        started = Date(value(.startedReading), format: "yyyy-MM-dd")
        finished = Date(value(.finishedReading), format: "yyyy-MM-dd")
        googleBooksId = value(.googleBooksId)
        manualBookId = row["Reading List ID"]
        isbn13 = ISBN13(value(.isbn13))
        language = value(.language)
        notes = value(.notes)
        currentPage = Int32(value(.currentPage))
        currentPercentage = Int32(value(.currentPercentage))
        pageCount = Int32(value(.pageCount))
        publicationDate = Date(value(.publicationDate), format: "yyyy-MM-dd")
        publisher = value(.publisher)
        if let ratingString = value(.rating), let ratingValue = Double(ratingString) {
            rating = ratingValue
        } else {
            rating = nil
        }
        subjects = value(.subjects)?.components(separatedBy: ";").compactMap { $0.trimming().nilIfWhitespace() } ?? []
        if let listsText = value(.lists) {
            lists = CSVRow.extractListDetail.allMatches(in: listsText).compactMap { match -> ListIndex? in
                guard match.captures.count == 3 else {
                    assertionFailure("Expected 3 capture groups, saw \(match.captures.count)")
                    return nil
                }
                guard let listName = match.captures[1], let listIndex = match.captures[2] else { return nil }
                guard let integerListIndex = Int32(listIndex) else { return nil }
                return ListIndex(listName: listName.trimming(), index: integerListIndex)
            }
        } else {
            lists = []
        }
    }

    init?(goodreadsRow row: [String: String]) {
        guard let title = row["Title"], let author = row["Author l-f"] else { return nil }
        self.title = title

        let firstAuthor: Author
        if let firstCommaPos = author.range(of: ","), let lastName = author[..<firstCommaPos.lowerBound].trimming().nilIfWhitespace() {
            firstAuthor = Author(lastName: lastName, firstNames: author[firstCommaPos.upperBound...].trimming().nilIfWhitespace())
        } else {
            firstAuthor = Author(lastName: author, firstNames: nil)
        }

        var additionalAuthors = [Author]()
        if let additionalAuthorsCell = row["Additional Authors"] {
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
        authors = [firstAuthor] + additionalAuthors

        let bookshelves = row["Bookshelves"]?.split(separator: ",").compactMap { $0.trimming().nilIfWhitespace() } ?? []

        if bookshelves.contains("read") || bookshelves.contains("currently-reading") {
            if let dateString = row["Date Read"] ?? row["Date Added"] {
                started = Date(dateString, format: "yyyy/MM/dd")
            } else {
                started = Date()
            }
        } else {
            started = nil
        }
        if bookshelves.contains("read") {
            if let dateString = row["Date Read"] ?? row["Date Added"] {
                finished = Date(dateString, format: "yyyy/MM/dd")
            } else {
                finished = Date()
            }
        } else {
            finished = nil
        }

        manualBookId = row["Book Id"]
        // The GoodReads export seems to present ISBN's like: ="9781231231231"
        isbn13 = ISBN13(row["ISBN13"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"=")))

        notes = row["My Review"]
        pageCount = Int32(row["Number of Pages"])
        publisher = row["Publisher"]

        if let ratingString = row["My Rating"], let ratingValue = Double(ratingString) {
            rating = ratingValue
        } else {
            rating = nil
        }

        subtitle = nil
        description = nil
        googleBooksId = nil
        language = nil
        currentPage = nil
        currentPercentage = nil
        publicationDate = nil
        subjects = []
        lists = []
    }
}
