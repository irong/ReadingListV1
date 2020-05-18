import Foundation
import CoreData
import UIKit
import ReadingList_Foundation

protocol ListBookDataProvider {
    func getBook(at indexPath: IndexPath) -> Book
}

// Two kinds of data providers: diffable and legacy.
@available(iOS 13.0, *)
protocol DiffableListBookDataProvider: ListBookDataProvider {
    func snapshot() -> NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
    var dataSource: ListBookDiffableDataSource? { get set }
}

@available(iOS, obsoleted: 13.0)
protocol LegacyListBookDataProvider: ListBookDataProvider {
    func count() -> Int
    func sectionCount() -> Int
    func rowCount(in section: Int) -> Int
    var dataSource: ListBookLegacyDataSource? { get set }
}

// MARK: FetchedResultsController-based data providers:

protocol ListBookControllerDataProvider: ListBookDataProvider {
    var controller: NSFetchedResultsController<Book> { get }
}

extension ListBookControllerDataProvider {
    func getBook(at indexPath: IndexPath) -> Book {
        return controller.object(at: indexPath)
    }
}

@available(iOS, obsoleted: 13.0)
final class LegacyListBookControllerDataProvider: ListBookControllerDataProvider, LegacyListBookDataProvider {
    let controller: NSFetchedResultsController<Book>
    weak var dataSource: ListBookLegacyDataSource?

    init(_ controller: NSFetchedResultsController<Book>) {
        self.controller = controller
    }

    func count() -> Int {
        return controller.fetchedObjects!.count
    }

    func sectionCount() -> Int {
        return controller.sections!.count
    }

    func rowCount(in section: Int) -> Int {
        return controller.sections![section].numberOfObjects
    }
}

@available(iOS 13.0, *)
final class DiffableListBookControllerDataProvider: ListBookControllerDataProvider, DiffableListBookDataProvider {
    private var changeMediator: ResultsControllerSnapshotGenerator<ListBookDiffableDataSource>!
    let controller: NSFetchedResultsController<Book>

    var dataSource: ListBookDiffableDataSource? {
        get { changeMediator.delegate }
        set { changeMediator.delegate = newValue }
    }

    init(_ controller: NSFetchedResultsController<Book>) {
        self.controller = controller

        // Set up the change mediator, which translates NSFetchedResultsControllerDelegate changes into snapshots
        self.changeMediator = ResultsControllerSnapshotGenerator<ListBookDiffableDataSource> { [unowned self] in
            self.snapshot()
        }
        self.controller.delegate = changeMediator.controllerDelegate
    }

    func snapshot() -> NSDiffableDataSourceSnapshot<String, NSManagedObjectID> {
        return controller.snapshot()
    }
}

// MARK: Set-based data providers:

protocol ListBookSetDataProvider: ListBookDataProvider {
    var books: [Book] { get }
    var filterPredicate: NSPredicate { get set }
}

extension ListBookSetDataProvider {
    func getBook(at indexPath: IndexPath) -> Book {
        guard indexPath.section == 0 else { preconditionFailure("Cannot request book at section \(indexPath.section)") }
        return books[indexPath.item]
    }
}

class BaseListBookSetDataProvider<DataSource: ListBookDataSource> {
    let list: List
    weak var dataSource: DataSource?
    
    var filterPredicate = NSPredicate(boolean: true) {
        didSet { buildBooksList() }
    }

    func buildBooksList() {
        books = list.books.filtered(using: filterPredicate).map { $0 as! Book }
    }

    /**
     The currently-displayed list of books.
     */
    private(set) var books: [Book]

    init(_ list: List) {
        self.list = list
        self.books = list.books.map { $0 as! Book }
        NotificationCenter.default.addObserver(self, selector: #selector(managedObjectContextChanged(_:)), name: .NSManagedObjectContextDidSave, object: list.managedObjectContext)
    }

    func handleSave(userInfo: [AnyHashable: Any]) {
        dataSource?.updateData(animate: true)
    }

    @objc final func managedObjectContextChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        buildBooksList()
        handleSave(userInfo: userInfo)
    }
}

@available(iOS, obsoleted: 13.0)
final class LegacyListBookSetDataProvider: BaseListBookSetDataProvider<ListBookLegacyDataSource>, ListBookSetDataProvider, LegacyListBookDataProvider {

    func count() -> Int {
        return books.count
    }

    func sectionCount() -> Int {
        return books.isEmpty ? 0 : 1
    }

    func rowCount(in section: Int) -> Int {
        guard section == 0 else { preconditionFailure() }
        return books.count
    }
}

@available(iOS 13.0, *)
final class DiffableListBookSetDataProvider: BaseListBookSetDataProvider<ListBookDiffableDataSource>, ListBookSetDataProvider, DiffableListBookDataProvider {
    private var updatedBookIds = [NSManagedObjectID]()

    override func handleSave(userInfo: [AnyHashable: Any]) {
        // We should remember which books have been changed, and store their IDs so we can request a reload of those rows in the next
        // snapshot generation. Otherwise, changes to books which were, and remain, in the list would not get picked up.
        // This variable will be used (and then cleared out) the next time snapshot() is called. There is a slight assumption that
        // it is only called by code which will actually apply the snapshot. But given that handleSave below will call updateData,
        // we should be fine.
        if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? NSSet {
            updatedBookIds = updatedObjects.compactMap { $0 as? Book }.filter { list.books.contains($0) }.map(\.objectID)
        }

        super.handleSave(userInfo: userInfo)
    }

    func snapshot() -> NSDiffableDataSourceSnapshot<String, NSManagedObjectID> {
        var snapshot = NSDiffableDataSourceSnapshot<String, NSManagedObjectID>()
        if !books.isEmpty {
            snapshot.appendSections([""])
            snapshot.appendItems(books.map(\.objectID), toSection: "")

            // Request a reload of any item which we detected as being changed.
            snapshot.reloadValidItems(updatedBookIds)
        }

        // and then clear out this
        updatedBookIds = []
        return snapshot
    }
}
