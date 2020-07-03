import Foundation
import CoreData
import Promises
import ReadingList_Foundation
import os.log

class BookCSVImporter {
    private let parserDelegate: BookCSVParserDelegate //swiftlint:disable:this weak_delegate

    init(format: ImportCSVFormat, settings: ImportSettings) {
        let backgroundContext = PersistentStoreManager.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        parserDelegate = BookCSVParserDelegate(context: backgroundContext, importFormat: format, settings: settings)
    }

    /**
     - Parameter completion: takes the following parameters:
        - error: if the CSV import failed irreversibly, this parameter will be non-nil
        - results: otherwise, this summary of the results of the import will be non-nil
    */
    func startImport(fromFileAt fileLocation: URL, _ completion: @escaping (Result<BookCSVImporter.Results, CSVImportError>) -> Void) {
        os_log("Beginning import from CSV file")
        parserDelegate.onCompletion = completion

        let parser = CSVParser(csvFileUrl: fileLocation)
        parser.delegate = parserDelegate
        parser.begin()
    }

    struct Results {
        let success: Int
        let error: Int
        let duplicate: Int
    }
}

class BookCSVParserDelegate: CSVParserDelegate {
    private let context: NSManagedObjectContext
    private let importFormat: ImportCSVFormat
    private let settings: ImportSettings
    private var cachedSorts: [BookReadState: BookSortIndexManager]
    private var networkOperations = [Promise<Void>]()

    var onCompletion: ((Result<BookCSVImporter.Results, CSVImportError>) -> Void)?

    init(context: NSManagedObjectContext, importFormat: ImportCSVFormat, settings: ImportSettings) {
        self.context = context
        self.importFormat = importFormat
        self.settings = settings

        cachedSorts = BookReadState.allCases.reduce(into: [BookReadState: BookSortIndexManager]()) { result, readState in
            // For imports, we ignore the "Add to Top" settings, and always add books downwards, in the order they appear in the CSV
            result[readState] = BookSortIndexManager(context: context, readState: readState, sortUpwards: false)
        }
    }

    func headersRead(_ headers: [String]) -> Bool {
        return headers.containsAll(importFormat.requiredHeaders)
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

    private func attach(_ listIndexes: [CSVRow.ListIndex], to book: Book) {
        for listIndex in listIndexes {
            let list = List.getOrCreate(inContext: context, withName: listIndex.listName)
            if let existingListItem = Array(book.listItems).first(where: { $0.list == list }) {
                existingListItem.sort = listIndex.index
            } else {
                _ = ListItem(context: context, book: book, list: list, sort: listIndex.index)
            }
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

    private func populateCover(forBook book: Book, withGoogleID googleID: String) -> Promise<Void> {
        return GoogleBooks.getCover(googleBooksId: googleID)
            .then { data -> Void in
                self.context.perform {
                    book.coverImage = data
                }
                os_log("Book supplemented with cover image for ID %s", type: .info, googleID)
            }
    }

    private func overwriteMetadata(forBook book: Book, withGoogleID googleID: String) -> Promise<Void> {
        return GoogleBooks.fetch(googleBooksId: googleID)
            .then { result -> Void in
                self.context.perform {
                    book.populate(fromFetchResult: result)
                }
                os_log("Book supplemented with metadata for ID %s", type: .info, googleID)
            }
    }

    private func lookupGoogleBooksId(forBook book: Book, withIsbn isbn: String) -> Promise<String> {
        return GoogleBooks.search(isbn: isbn)
            .validate { $0.count == 1 }
            .then { data -> String in
                return data[0].id
            }
    }

    private func findExistingBook(_ csvRow: CSVRow) -> Book? {
        if let googleBooksId = csvRow.googleBooksId, let existingBookByGoogleId = Book.get(fromContext: self.context, googleBooksId: googleBooksId) {
            return existingBookByGoogleId
        }
        if let isbn = csvRow.isbn13, let existingBookByIsbn = Book.get(fromContext: self.context, isbn: isbn.string) {
            return existingBookByIsbn
        }
        return nil
    }

    func lineParseSuccess(_ values: [String: String]) {
        guard let csvRow = CSVRow(for: importFormat, row: values) else {
            invalidCount += 1
            os_log("Invalid data: no book created")
            return
        }

        // FUTURE: Batch save
        context.performAndWait { [unowned self] in
            let book: Book
            if let existingBook = findExistingBook(csvRow) {
                guard settings.overwriteExistingBooks else {
                    duplicateCount += 1
                    return
                }
                book = existingBook
            } else {
                book = Book(context: self.context)
                guard let sortManager = cachedSorts[book.readState] else { preconditionFailure() }
                book.sort = sortManager.getAndIncrementSort()
            }
            book.populate(fromCsvRow: csvRow)
            book.subjects.formUnion(createSubjects(csvRow.subjects))
            attach(csvRow.lists, to: book)

            // If the book is not valid, delete it
            let objectIdForLogging = book.objectID.uriRepresentation().absoluteString
            do {
                try book.validateForUpdate()
            } catch {
                invalidCount += 1
                os_log("Invalid book: deleting book %{public}s (%{public}s)", type: .info, objectIdForLogging, error.localizedDescription)
                book.delete()
                return
            }
            os_log("Created %{public}s", objectIdForLogging)
            successCount += 1

            if let googleBooksId = book.googleBooksId {
                if settings.downloadCoverImages && book.coverImage == nil {
                    os_log("Supplementing book %{public}s with cover image from google ID %s", type: .info, objectIdForLogging, googleBooksId)
                    networkOperations.append(populateCover(forBook: book, withGoogleID: googleBooksId))
                }
                if settings.downloadMetadata {
                    os_log("Supplementing book %{public}s with metadata from google ID %s", type: .info, objectIdForLogging, googleBooksId)
                    networkOperations.append(overwriteMetadata(forBook: book, withGoogleID: googleBooksId))
                }
            } else if let isbn = book.isbn13, let isbnString = ISBN13(isbn)?.string {
                if settings.downloadCoverImages || settings.downloadMetadata {
                    os_log("Supplementing book %{public}s with Google Books ID from ISBN %s", type: .info, objectIdForLogging, isbnString)
                    let googleIdLookup = lookupGoogleBooksId(forBook: book, withIsbn: isbnString)

                    if settings.downloadMetadata {
                        os_log("Supplementing book %{public}s with cover image from google ID", type: .info, objectIdForLogging)
                        networkOperations.append(googleIdLookup.then {
                            self.overwriteMetadata(forBook: book, withGoogleID: $0)
                        })
                    }
                    if book.coverImage == nil && settings.downloadCoverImages {
                        os_log("Supplementing book %{public}s with metadata from google ID", type: .info, objectIdForLogging)
                        networkOperations.append(googleIdLookup.then {
                            self.populateCover(forBook: book, withGoogleID: $0)
                        })
                    }
                }
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
        all(networkOperations)
            .always(on: .main) {
                os_log("All %d network operations promises completed", type: .info, self.networkOperations.count)
                self.context.performAndWait {
                    // FUTURE: Consider tidying up any clashing list indexes
                    os_log("Saving results of CSV import (%d of %d successful)", self.successCount, self.successCount + self.invalidCount + self.duplicateCount)
                    self.context.saveAndLogIfErrored()
                }
                let results = BookCSVImporter.Results(success: self.successCount, error: self.invalidCount, duplicate: self.duplicateCount)
                self.onCompletion?(.success(results))
            }
    }
}
