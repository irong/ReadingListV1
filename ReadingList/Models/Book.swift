import Foundation
import CoreData
import ReadingList_Foundation
import os.log

@objc(Book)
class Book: NSManagedObject {

    /**
     The read state of a book is determined by the presence or absence of the startedReading and finishedReading
     dates. It exists as a core data attribute primarily to allow its use as a section keypath.
     */
    @NSManaged private(set) var readState: BookReadState
    @NSManaged private(set) var startedReading: Date?
    @NSManaged private(set) var finishedReading: Date?

    @NSManaged var googleBooksId: String?
    @NSManaged var manualBookId: String?
    @NSManaged var title: String
    @NSManaged private(set) var authorSort: String
    @NSManaged var publicationDate: Date?
    @NSManaged var publisher: String?
    @NSManaged var bookDescription: String?
    @NSManaged var coverImage: Data?
    @NSManaged var notes: String?
    @NSManaged var languageCode: String? // ISO 639.1: two-digit language code
    @NSManaged var subjects: Set<Subject>
    @NSManaged private(set) var lists: Set<List>

    func setToRead() {
        readState = .toRead
        startedReading = nil
        finishedReading = nil
        currentPage = nil
    }

    func setReading(started: Date) {
        readState = .reading
        startedReading = started
        finishedReading = nil
    }

    func setFinished(started: Date, finished: Date) {
        readState = .finished
        startedReading = started
        if finished >= started {
            finishedReading = finished
        } else {
            finishedReading = started
        }
        currentPage = nil
    }

    /**
     Enumerates the attributes which are not represented as standard NSManaged variables. These are usually
     the optional numerical attributes, which are much more convenient to use when handled manually in their
     Swift types, than represented as @NSManaged optional NSNumber objects.
    */
    enum Key: String {
        //swiftlint:disable redundant_string_enum_value
        case authors = "authors"
        case isbn13 = "isbn13"
        case pageCount = "pageCount"
        case currentPage = "currentPage"
        case rating = "rating"
        case sort = "sort"
        //swiftlint:enable redundant_string_enum_value
    }

    private func safelyGetPrimitiveValue(_ key: Book.Key) -> Any? {
        return safelyGetPrimitiveValue(forKey: key.rawValue)
    }

    private func safelySetPrimitiveValue(_ value: Any?, _ key: Book.Key) {
        return safelySetPrimitiveValue(value, forKey: key.rawValue)
    }

    // The following variables are manually managed rather than using @NSManaged, to allow non-objc types
    // to be used, or to allow us to hook into the setter, to update other properties automatically.

    @objc var authors: [Author] {
        get { return (safelyGetPrimitiveValue(forKey: #keyPath(Book.authors)) as! [Author]?) ?? [] }
        set {
            safelySetPrimitiveValue(newValue, forKey: #keyPath(Book.authors))
            authorSort = newValue.lastNamesSort
        }
    }

    var isbn13: Int64? {
        get { return safelyGetPrimitiveValue(.isbn13) as! Int64? }
        set { safelySetPrimitiveValue(newValue, .isbn13) }
    }

    var pageCount: Int32? {
        get { return safelyGetPrimitiveValue(.pageCount) as! Int32? }
        set { safelySetPrimitiveValue(newValue, .pageCount) }
    }

    var currentPage: Int32? {
        get { return safelyGetPrimitiveValue(.currentPage) as! Int32? }
        set { safelySetPrimitiveValue(newValue, .currentPage) }
    }

    var rating: Int16? {
        get { return safelyGetPrimitiveValue(.rating) as! Int16? }
        set { safelySetPrimitiveValue(newValue, .rating) }
    }

    var sort: Int32? {
        get { return safelyGetPrimitiveValue(.sort) as! Int32? }
        set { safelySetPrimitiveValue(newValue, .sort) }
    }

    override func willSave() {
        super.willSave()

        // FUTURE: willSave() is called after property validation, so if we add sort/readState validation
        // then this removal of the sort property will need to be done earlier.
        setSort()
    }

    private func setSort() {
        guard readState == .toRead else {
            if sort != nil { sort = nil }
            return
        }
        guard sort == nil else { return }

        if let maximalSort = Book.maximalSort(getMaximum: !UserDefaults.standard[.addBooksToTopOfCustom], fromContext: managedObjectContext!) {
            let plusMinusOne: Int32 = UserDefaults.standard[.addBooksToTopOfCustom] ? -1 : 1
            sort = maximalSort + plusMinusOne
        } else {
            sort = 0
        }
    }

    override func prepareForDeletion() {
        super.prepareForDeletion()
        for orphanedSubject in subjects.filter({ $0.books.count == 1 }) {
            orphanedSubject.delete()
            os_log("Orphaned subject %{public}s deleted.", type: .info, orphanedSubject.name)
        }
    }
}

extension Book {

    // FUTURE: make a convenience init which takes a fetch result?
    func populate(fromFetchResult fetchResult: FetchResult) {
        googleBooksId = fetchResult.id
        title = fetchResult.title
        authors = fetchResult.authors
        bookDescription = fetchResult.description
        subjects = Set(fetchResult.subjects.map { Subject.getOrCreate(inContext: self.managedObjectContext!, withName: $0) })
        coverImage = fetchResult.coverImage
        pageCount = fetchResult.pageCount
        publicationDate = fetchResult.publishedDate
        publisher = fetchResult.publisher
        isbn13 = fetchResult.isbn13?.int
        languageCode = fetchResult.languageCode
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
            isbnFetch.predicate = NSPredicate(format: "%K == %@", Book.Key.isbn13.rawValue, isbn)
            isbnFetch.returnsObjectsAsFaults = false
            return (try! context.fetch(isbnFetch)).first
        }

        return nil
    }

    /**
     Gets the "maximal" sort value of any book - i.e. either the maximum or minimum value.
    */
    static func maximalSort(getMaximum: Bool, fromContext context: NSManagedObjectContext) -> Int32? {
        // The following code could (and in fact was) rewritten to use an NSExpression to just grab the max or min
        // sort, but it crashes when the store type is InMemoryStore (as it is in tests). Would need to rewrite
        // the unit tests to use SQL stores. See https://stackoverflow.com/a/13681549/5513562
        let fetchRequest = NSManagedObject.fetchRequest(Book.self, limit: 1)
        fetchRequest.predicate = NSPredicate.and([
            NSPredicate(format: "%K == %ld", #keyPath(Book.readState), BookReadState.toRead.rawValue),
            NSPredicate(format: "%K != nil", Book.Key.sort.rawValue)])
        fetchRequest.sortDescriptors = [NSSortDescriptor(Book.Key.sort.rawValue, ascending: !getMaximum)]
        fetchRequest.returnsObjectsAsFaults = false
        return (try! context.fetch(fetchRequest)).first?.sort
    }

    static func maxSort(fromContext context: NSManagedObjectContext) -> Int32? {
        return maximalSort(getMaximum: true, fromContext: context)
    }

    static func minSort(fromContext context: NSManagedObjectContext) -> Int32? {
        return maximalSort(getMaximum: false, fromContext: context)
    }
}
