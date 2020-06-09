import Foundation
import CoreData
import Promises
import ReadingList_Foundation
import os.log

class BookCSVImporter {
    private let parserDelegate: BookCSVParserDelegate //swiftlint:disable:this weak_delegate
    var parser: CSVParser?

    init(includeImages: Bool = true) {
        let backgroundContext = PersistentStoreManager.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        parserDelegate = BookCSVParserDelegate(context: backgroundContext, includeImages: includeImages)
    }

    /**
     - Parameter completion: takes the following parameters:
        - error: if the CSV import failed irreversibly, this parameter will be non-nil
        - results: otherwise, this summary of the results of the import will be non-nil
    */
    func startImport(fromFileAt fileLocation: URL, _ completion: @escaping (Result<BookCSVImportResults, CSVImportError>) -> Void) {
        os_log("Beginning import from CSV file")
        parserDelegate.onCompletion = completion

        parser = CSVParser(csvFileUrl: fileLocation)
        parser!.delegate = parserDelegate
        parser!.begin()
    }
}

struct BookCSVImportResults {
    let success: Int
    let error: Int
    let duplicate: Int
}

enum ImportCsvFormat {
    case native
    case goodreads
}

protocol CsvRow {
    var title: String { get }
    var authors: [Author] { get }
    var subtitle: String? { get }
    var description: String? { get }
    var started: Date? { get }
    var finished: Date? { get }
    var googleBooksId: String? { get }
    var isbn13: ISBN13? { get }
    var language: String? { get }
    var notes: String? { get }
    var currentPage: Int32? { get }
    var currentPercentage: Int32? { get }
    var pageCount: Int32? { get }
    var publicationDate: Date? { get }
    var publisher: String? { get }
    var rating: Int16? { get }
    var subjects: [String] { get }
}

class CsvRow {
    static let requiredHeaders = ["Title", "Authors"]
    init?(_ values: [String: String]) {
        guard let title = values["Title"], let authors = values["Authors"] else { return nil }
        self.values = values
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
    
    var values: [String: String]
    var title: String
    var authors: [Author]
    var subtitle: String? { values["Subtitle"] }
    var description: String? { values["Description"] }
    var started: Date? { Date(values["Started Reading"], format: "yyyy-MM-dd") }
    var finished: Date? { Date(values["Finished Reading"], format: "yyyy-MM-dd") }
    var googleBooksId: String? { values["Google Books ID"] }
    var isbn13: ISBN13? { ISBN13(values["ISBN-13"]) }
    var language: String? { values["Language Code"] }
    var notes: String? { values["Notes"] }
    var currentPage: Int32? { Int32(values["Current Page"]) }
    var currentPercentage: Int32? { Int32(values["Current Percentage"]) }
    var pageCount: Int32? { Int32(values["Page Count"]) }
    var publicationDate: Date? { Date(values["Publication Date"], format: "yyyy-MM-dd") }
    var publisher: String? { values["Publisher"] }
    var rating: Int16? {
        guard let ratingString = values["Rating"], let ratingValue = Double(ratingString) else { return nil }
        return Int16(floor(ratingValue * 2))
    }
    var subjects: [String] { values["Subjects"]?.components(separatedBy: ";").compactMap { $0.trimming().nilIfWhitespace() } ?? [] }
}

class CsvGoodReadsRow: CsvRow {
    static let requiredHeaders = ["Title", "Author l-f"]
    
    override init?(_ values: [String : String]) {
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
    }
    var bookshelves: [String] {
        values["Bookshelves"]?.split(separator: ",").compactMap { $0.trimming().nilIfWhitespace() } ?? []
    }
    
    override var subtitle: String? { nil }
    override var started: Date? {
        guard bookshelves.contains("read") || bookshelves.contains("currently-reading") else { return nil }
        if let dateString = values["Date Read"] ?? values["Date Added"] {
            return Date(dateString, format: "yyyy/MM/dd")
        } else {
             return Date()
        }
    }
    override var finished: Date? {
        guard bookshelves.contains("read") else { return nil }
        if let dateString = values["Date Read"] ?? values["Date Added"] {
            return Date(dateString, format: "yyyy/MM/dd")
        } else {
            return Date()
        }
    }
    override var googleBooksId: String? { nil }
    override var isbn13: ISBN13? {
        // The GoodReads export seems to present ISBN's like: ="9781231231231"
        ISBN13(values["ISBN13"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"=")))
    }
    override var language: String? { nil }
    override var notes: String? { values["My Review"] }
    override var currentPage: Int32? { nil }
    override var currentPercentage: Int32? { nil }
    override var pageCount: Int32? { Int32(values["Number of Pages"]) }
    override var publicationDate: Date? { nil }
    override var publisher: String? { values["Publisher"] }
    override var rating: Int16? {
        guard let ratingString = values["My Rating"], let ratingValue = Double(ratingString) else { return nil }
        return Int16(floor(ratingValue * 2))
    }
    override var subjects: [String] { [] }
}

class BookCSVParserDelegate: CSVParserDelegate {
    private let context: NSManagedObjectContext
    private let includeImages: Bool
    private var cachedSorts: [BookReadState: BookSortIndexManager]
    private var coverDownloadPromises = [Promise<Void>]()
    private var listMappings = [String: [(bookID: NSManagedObjectID, index: Int)]]()
    private var listNames = [String]()

    let importFormat: ImportCsvFormat
    var onCompletion: ((Result<BookCSVImportResults, CSVImportError>) -> Void)?

    init(context: NSManagedObjectContext, importFormat: ImportCsvFormat, includeImages: Bool = true) {
        self.context = context
        self.importFormat = importFormat
        self.includeImages = includeImages

        cachedSorts = BookReadState.allCases.reduce(into: [BookReadState: BookSortIndexManager]()) { result, readState in
            // For imports, we ignore the "Add to Top" settings, and always add books downwards, in the order they appear in the CSV
            result[readState] = BookSortIndexManager(context: context, readState: readState, sortUpwards: false)
        }
    }

    func headersRead(_ headers: [String]) -> Bool {
        let requiredHeaders: [String]
        switch importFormat {
        case .goodreads:
            requiredHeaders = CsvGoodReadsRow.requiredHeaders
        case .native:
            requiredHeaders = CsvRow.requiredHeaders
        }
        
        if !headers.containsAll(requiredHeaders) {
            return false
        }
        
        if importFormat == .native {
            listNames = headers.filter { !BookCSVExport.headers.contains($0) }
        }
        return true
    }

    private func createBook(_ values: CsvRow) -> Book? {
        let book = Book(context: self.context)
        book.title = values.title
        book.subtitle = values.subtitle
        book.authors = values.authors
        book.googleBooksId = values.googleBooksId
        book.isbn13 = values.isbn13?.int
        let manualId = values[fieldToColumn.manualId]
        book.manualBookId = book.googleBooksId == nil ? (manualId == nil ? UUID().uuidString : manualId) : nil
        book.pageCount = values.pageCount
        if let page = values.currentPage {
            book.setProgress(.page(page))
        } else if let percentage = values.currentPercentage {
            book.setProgress(.percentage(percentage))
        }
        book.notes = values.notes?.replacingOccurrences(of: "\r\n", with: "\n")
        book.publicationDate = values.publicationDate
        book.publisher = values.publisher
        book.bookDescription = values.description?.replacingOccurrences(of: "\r\n", with: "\n")
        if let started = values.started {
            if let finished = values.finished {
                book.setFinished(started: started, finished: finished)
            } else {
                book.setReading(started: started)
            }
        } else {
            book.setToRead()
        }

        book.subjects = Set(createSubjects(values.subjects))
        book.rating = values.rating
        if let language = values.language {
            book.language = LanguageIso639_1(rawValue: language)
        }
        return book
    }

    private func createAuthors(_ authorString: String) -> [Author] {
        return authorString.components(separatedBy: ";").compactMap {
            guard let authorString = $0.trimming().nilIfWhitespace() else { return nil }
            if let firstCommaPos = authorString.range(of: ","), let lastName = authorString[..<firstCommaPos.lowerBound].trimming().nilIfWhitespace() {
                return Author(lastName: lastName, firstNames: authorString[firstCommaPos.upperBound...].trimming().nilIfWhitespace())
            } else {
                return Author(lastName: authorString, firstNames: nil)
            }
        }
    }

    private func createSubjects(_ subjects: [String]) -> [Subject] {
        return subjects.map {
            Subject.getOrCreate(inContext: context, withName: $0)
        }
    }

    private func populateLists() {
        for listMapping in listMappings {
            let list = getOrCreateList(withName: listMapping.key)
            let orderedBooks = listMapping.value.sorted { $0.1 < $1.1 }
                .map { context.object(with: $0.bookID) as! Book }
                .filter { !list.books.contains($0) }
            list.addBooks(orderedBooks)
        }
    }

    private func getOrCreateList(withName name: String) -> List {
        let listFetchRequest = NSManagedObject.fetchRequest(List.self, limit: 1)
        listFetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(List.name), name)
        listFetchRequest.returnsObjectsAsFaults = false
        if let existingList = (try! context.fetch(listFetchRequest)).first {
            return existingList
        }
        return List(context: context, name: name)
    }

    private func populateCover(forBook book: Book, withGoogleID googleID: String) {
        coverDownloadPromises.append(GoogleBooks.getCover(googleBooksId: googleID)
            .then { data -> Void in
                self.context.perform {
                    book.coverImage = data
                }
                os_log("Book supplemented with cover image for ID %s", type: .info, googleID)
            }
        )
    }

    func lineParseSuccess(_ values: [String: String]) {
        let fieldToColumn = values[fieldToColumnGoodReads.author] == nil ? fieldToColumnNative : fieldToColumnGoodReads

        // FUTURE: Batch save
        context.performAndWait { [unowned self] in
            // Check for duplicates
            if let googleBooksId = values[fieldToColumn.googleBooksId], let existingBookByGoogleId = Book.get(fromContext: self.context, googleBooksId: googleBooksId) {
                os_log("Skipping duplicate book: Google Books ID %s already exists in %{public}s", type: .info, googleBooksId, existingBookByGoogleId.objectID.uriRepresentation().absoluteString)
                duplicateCount += 1
                return
            }
            if let isbn = values[fieldToColumn.isbn13], let existingBookByIsbn = Book.get(fromContext: self.context, isbn: isbn) {
                os_log("Skipping duplicate book: ISBN %s already exists in %{public}s", type: .info, isbn, existingBookByIsbn.objectID.uriRepresentation().absoluteString)
                duplicateCount += 1
                return
            }

            guard let newBook = createBook(values, fieldToColumn) else {
                invalidCount += 1
                os_log("Invalid data: no book created")
                return
            }
            guard let sortManager = cachedSorts[newBook.readState] else { preconditionFailure() }
            newBook.sort = sortManager.getAndIncrementSort()

            // If the book is not valid, delete it
            let objectIdForLogging = newBook.objectID.uriRepresentation().absoluteString
            guard newBook.isValidForUpdate() else {
                invalidCount += 1
                os_log("Invalid book: deleting book %{public}s", type: .info, objectIdForLogging)
                newBook.delete()
                return
            }
            os_log("Created %{public}s", objectIdForLogging)
            successCount += 1

            // Record the list memberships
            for listName in listNames {
                if let listPosition = Int(values[listName]) {
                    if listMappings[listName] == nil { listMappings[listName] = [] }
                    listMappings[listName]!.append((newBook.objectID, listPosition))
                }
            }
            // FUTURE: Lookup googleBooksId from isbn13 when nil
            // Supplement the book with the cover image
            if self.includeImages, let googleBooksId = newBook.googleBooksId {
                os_log("Supplementing book %{public}s with cover image from google ID %s", type: .info, objectIdForLogging, googleBooksId)
                populateCover(forBook: newBook, withGoogleID: googleBooksId)
            }
        }
    }

    private var duplicateCount = 0
    private var invalidCount = 0
    private var successCount = 0

    func lineParseError() {
        invalidCount += 1
    }

    func onFailure(_ error: CSVImportError) {
        onCompletion?(.failure(error))
    }

    func completion() {
        all(coverDownloadPromises)
            .always(on: .main) {
                os_log("All %d book cover download promises completed", type: .info, self.coverDownloadPromises.count)
                self.context.performAndWait {
                    self.populateLists()
                    os_log("Saving results of CSV import (%d of %d successful)", self.successCount, self.successCount + self.invalidCount + self.duplicateCount)
                    self.context.saveAndLogIfErrored()
                }
                let results = BookCSVImportResults(success: self.successCount, error: self.invalidCount, duplicate: self.duplicateCount)
                self.onCompletion?(.success(results))
            }
    }
}
