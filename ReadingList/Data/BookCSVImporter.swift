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

class BookCSVParserDelegate: CSVParserDelegate {
    private let context: NSManagedObjectContext
    private let includeImages: Bool
    private var cachedSorts: [BookReadState: BookSortIndexManager]
    private var coverDownloadPromises = [Promise<Void>]()
    private var listMappings = [String: [(bookID: NSManagedObjectID, index: Int)]]()
    private var listNames = [String]()
    private var fieldToColumnNative: [String: String] = [
        "authors": "Authors",
        "bookDescription": "Description",
        "finished": "Finished Reading",
        "googleBooksId": "Google Books ID",
        "isbn13": "ISBN-13",
        "language": "Language Code",
        "notes": "Notes",
        "page": "Current Page",
        "pageCount": "Page Count",
        "percentage": "Current Percentage",
        "publicationDate": "Publication Date",
        "publisher": "Publisher",
        "rating": "Rating",
        "started": "Started Reading",
        "subjects": "Subjects",
        "title": "Title"
    ]

    private var fieldToColumnGoodReads: [String: String] = [
        "authors": "Author l-f",
        "bookDescription": "Description",
        "finished": "Date Read",
        "isbn13": "ISBN13",
        "notes": "My Review",
        "pageCount": "Number of Pages",
        "publicationDate": "Year Published",
        "publisher": "Publisher",
        "rating": "My Rating",
        "started": "Date Added",
        "title": "Title",
        "manualId": "Book Id"
    ]

    var onCompletion: ((Result<BookCSVImportResults, CSVImportError>) -> Void)?

    init(context: NSManagedObjectContext, includeImages: Bool = true) {
        self.context = context
        self.includeImages = includeImages

        cachedSorts = BookReadState.allCases.reduce(into: [BookReadState: BookSortIndexManager]()) { result, readState in
            // For imports, we ignore the "Add to Top" settings, and always add books downwards, in the order they appear in the CSV
            result[readState] = BookSortIndexManager(context: context, readState: readState, sortUpwards: false)
        }
    }

    func headersRead(_ headers: [String]) -> Bool {
        if !(headers.contains(fieldToColumnNative.title) || headers.contains(fieldToColumnGoodReads.title)) ||
            !(headers.contains(fieldToColumnNative.authors) || headers.contains(fieldToColumnGoodReads.authors)
            ) {
            return false
        }
        listNames = headers.filter { !BookCSVExport.headers.contains($0) }
        return true
    }

    private func createBook(_ values: [String: String], fieldToColumn: [String: String]) -> Book? {
        guard let title = values[fieldToColumn.title] else { return nil }
        guard let authors = values[fieldToColumn.authors] else { return nil }
        let book = Book(context: self.context)
        book.title = title
        book.subtitle = values["Subtitle"]
        book.authors = createAuthors(authors)
        book.googleBooksId = values[fieldToColumn.googleBooksId]
        book.isbn13 = ISBN13(values[fieldToColumn.isbn13])?.int
        let manualId = values[fieldToColumn.manualId]
        book.manualBookId = book.googleBooksId == nil ? (manualId == nil ? UUID().uuidString : manualId) : nil
        book.pageCount = Int32(values[fieldToColumn.pageCount])
        if let page = Int32(values[fieldToColumn.page]) {
            book.setProgress(.page(page))
        } else if let percentage = Int32(values[fieldToColumn.percentage]) {
            book.setProgress(.percentage(percentage))
        }
        book.notes = values[fieldToColumn.notes]?.replacingOccurrences(of: "\r\n", with: "\n")
        book.publicationDate = Date(iso: values[fieldToColumn.publicationDate])
        book.publisher = values[fieldToColumn.publisher]
        book.bookDescription = values[fieldToColumn.bookDescription]?.replacingOccurrences(of: "\r\n", with: "\n")
        if let started = Date(iso: values[fieldToColumn.started]) {
            if let finished = Date(iso: values[fieldToColumn.finished]) {
                book.setFinished(started: started, finished: finished)
            } else {
                let isGoodReads = fieldToColumn == fieldToColumnGoodReads
                if !isGoodReads || (isGoodReads && values["Bookshelves"].contains("currently-reading")) {
                    book.setReading(started: started)
                }
            }
        } else {
            book.setToRead()
        }

        book.subjects = Set(createSubjects(values[fieldToColumn.subjects]))
        book.rating = Int16(values[fieldToColumn.rating])
        if ![1, 2, 3, 4, 5].contains(book.rating) {
            book.rating = ""
        }
        book.language = LanguageIso639_1(rawValue: values[fieldToColumn.language] ?? "")
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

    private func createSubjects(_ subjects: String?) -> [Subject] {
        guard let subjects = subjects else { return [] }
        return subjects.components(separatedBy: ";").compactMap {
            guard let subjectString = $0.trimming().nilIfWhitespace() else { return nil }
            return Subject.getOrCreate(inContext: context, withName: subjectString)
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
