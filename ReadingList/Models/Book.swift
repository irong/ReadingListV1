import Foundation
import CoreData

@objc(Book)
class Book: NSManagedObject {
    @NSManaged var readState: BookReadState
    @NSManaged var startedReading: Date?
    @NSManaged var finishedReading: Date?

    @NSManaged var isbn13: String?
    @NSManaged var googleBooksId: String?
    @NSManaged var manualBookId: String?

    @NSManaged var title: String
    @NSManaged private(set) var authors: [Author]
    @NSManaged private(set) var authorSort: String // Calculated sort helper

    @NSManaged var pageCount: NSNumber?
    @NSManaged var publicationDate: Date?
    @NSManaged var bookDescription: String?
    @NSManaged var coverImage: Data?
    @NSManaged var notes: String?
    @NSManaged var rating: NSNumber? // Valid values are 1-5.
    @NSManaged var languageCode: String? // ISO 639.1: two-digit language code
    @NSManaged var currentPage: NSNumber?
    @NSManaged var sort: NSNumber?

    @NSManaged var subjects: Set<Subject>
    @NSManaged private(set) var lists: Set<List>

    convenience init(context: NSManagedObjectContext, readState: BookReadState) {
        self.init(context: context)
        self.readState = readState
        if readState == .reading {
            startedReading = Date()
        }
        if readState == .finished {
            startedReading = Date()
            finishedReading = Date()
        }
    }

    override func willSave() {
        super.willSave()

        // The sort manipulation should be in a method which allows setting of dates
        if readState == .toRead && sort == nil {
            let maxSort = Book.maxSort(fromContext: managedObjectContext!) ?? 0
            self.sort = (maxSort + 1).nsNumber
        }

        // Sort is not (yet) supported for non To Read books
        if readState != .toRead && sort != nil {
            self.sort = nil
        }
    }

    override func prepareForDeletion() {
        super.prepareForDeletion()
        for orphanedSubject in subjects.filter({ $0.books.count == 1 }) {
            orphanedSubject.delete()
            print("orphaned subject \(orphanedSubject.name) deleted.")
        }
    }
}

extension Book {

    func setAuthors(_ authors: [Author]) {
        self.authors = authors
        self.authorSort = Author.authorSort(authors)
    }

    // FUTURE: make a convenience init which takes a fetch result?
    func populate(fromFetchResult fetchResult: GoogleBooks.FetchResult) {
        googleBooksId = fetchResult.id
        title = fetchResult.title
        populateAuthors(fromStrings: fetchResult.authors)
        bookDescription = fetchResult.description
        subjects = Set(fetchResult.subjects.map { Subject.getOrCreate(inContext: self.managedObjectContext!, withName: $0) })
        coverImage = fetchResult.coverImage
        pageCount = fetchResult.pageCount?.nsNumber
        publicationDate = fetchResult.publishedDate
        isbn13 = fetchResult.isbn13
        languageCode = fetchResult.languageCode
    }

    func populate(fromSearchResult searchResult: GoogleBooks.SearchResult, withCoverImage coverImage: Data? = nil) {
        googleBooksId = searchResult.id
        title = searchResult.title
        populateAuthors(fromStrings: searchResult.authors)
        isbn13 = searchResult.isbn13
        self.coverImage = coverImage
    }

    private func populateAuthors(fromStrings authors: [String]) {
        let authorNames: [(String?, String)] = authors.map {
            if let range = $0.range(of: " ", options: .backwards) {
                let firstNames = $0[..<range.upperBound].trimming()
                let lastName = $0[range.lowerBound...].trimming()

                return (firstNames: firstNames, lastName: lastName)
            } else {
                return (firstNames: nil, lastName: $0)
            }
        }

        self.setAuthors(authorNames.map { Author(lastName: $0.1, firstNames: $0.0) })
    }

    static func get(fromContext context: NSManagedObjectContext, googleBooksId: String? = nil, isbn: String? = nil) -> Book? {
        // if both are nil, leave early
        guard googleBooksId != nil || isbn != nil else { return nil }

        // First try fetching by google books ID
        if let googleBooksId = googleBooksId {
            let googleBooksfetch = NSManagedObject.fetchRequest(Book.self, limit: 1)
            googleBooksfetch.predicate = NSPredicate(format: "%K == %@", #keyPath(Book.googleBooksId), googleBooksId)
            googleBooksfetch.returnsObjectsAsFaults = false
            if let result = (try! context.fetch(googleBooksfetch)).first { return result }
        }

        // then try fetching by ISBN
        if let isbn = isbn {
            let isbnFetch = NSManagedObject.fetchRequest(Book.self, limit: 1)
            isbnFetch.predicate = NSPredicate(format: "%K == %@", #keyPath(Book.isbn13), isbn)
            isbnFetch.returnsObjectsAsFaults = false
            return (try! context.fetch(isbnFetch)).first
        }

        return nil
    }

    static func maxSort(fromContext context: NSManagedObjectContext) -> Int32? {
        // FUTURE: Could use a fetch expression to just return the max value
        let fetchRequest = NSManagedObject.fetchRequest(Book.self, limit: 1)
        fetchRequest.predicate = NSPredicate(format: "%K == %ld", #keyPath(Book.readState), BookReadState.toRead.rawValue)
        fetchRequest.sortDescriptors = [NSSortDescriptor(\Book.sort, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        return (try! context.fetch(fetchRequest)).first?.sort?.int32
    }

    enum ValidationError: Error {
        case missingTitle
        case invalidIsbn
        case invalidReadDates
        case invalidLanguageCode
        case missingIdentifier
        case conflictingIdentifiers
    }

    override func validateForUpdate() throws {
        try super.validateForUpdate()

        // FUTURE: these should be property validators, not in validateForUpdate
        if title.isEmptyOrWhitespace { throw ValidationError.missingTitle }
        if let isbn = isbn13, ISBN13(isbn) == nil { throw ValidationError.invalidIsbn }

        // FUTURE: Check read state with current page
        if readState == .toRead && (startedReading != nil || finishedReading != nil) { throw ValidationError.invalidReadDates }
        if readState == .reading && (startedReading == nil || finishedReading != nil) { throw ValidationError.invalidReadDates }
        if readState == .finished && (startedReading == nil || finishedReading == nil
            || startedReading!.startOfDay() > finishedReading!.startOfDay()) {
            throw ValidationError.invalidReadDates
        }

        if googleBooksId == nil && manualBookId == nil {
            throw ValidationError.missingIdentifier
        }
        if googleBooksId != nil && manualBookId != nil {
            throw ValidationError.conflictingIdentifiers
        }

        if let isoCode = languageCode, Language.byIsoCode[isoCode] == nil {
            throw ValidationError.invalidLanguageCode
        }
    }

    func startReading() {
        guard readState == .toRead else { print("Attempted to start a book in state \(readState)"); return }
        readState = .reading
        startedReading = Date()
    }

    func finishReading() {
        guard readState == .reading else { print("Attempted to finish a book in state \(readState)"); return }
        readState = .finished
        finishedReading = Date()
    }
}
