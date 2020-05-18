import Foundation
import CoreData
import UIKit
import ReadingList_Foundation

// TODO Diffable mode doesn't update table headers.

protocol ListBookDataSource: class, UITableViewEmptyDetectingDataSource {
    func updateData(animate: Bool)
    func getBook(at indexPath: IndexPath) -> Book
    var list: List { get }
    var searchController: UISearchController { get }
    var controllerDataProvider: ListBookControllerDataProvider? { get }
    var setDataProvider: ListBookSetDataProvider? { get }
}

extension ListBookDataSource {
    func canMoveRow() -> Bool {
        guard !searchController.hasActiveSearchTerms else { return false }
        // Lists with a custom ordering use a Set data provider
        guard let setDataProvider = setDataProvider else { return false }
        return setDataProvider.books.count > 1
    }

    func moveRow(at sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard !searchController.hasActiveSearchTerms else { return }
        guard sourceIndexPath != destinationIndexPath else { return }
        guard let setDataProvider = setDataProvider else { return }

        // Disable change notification updates. Since we could be running this code in either of a diffable or legacy data source,
        // with corresponding diffable or legacy data provider, we need to do some verbose type checks. It isn't trivial to expose
        // a generic property which works in all cases.
        if #available(iOS 13.0, *), let diffableSetDataProvider = setDataProvider as? DiffableListBookSetDataProvider {
            diffableSetDataProvider.dataSource = nil
        } else if let legacySetDataProvider = setDataProvider as? LegacyListBookSetDataProvider {
            legacySetDataProvider.dataSource = nil
        } else {
            preconditionFailure()
        }

        var books = list.books.map { $0 as! Book }
        let movedBook = books.remove(at: sourceIndexPath.row)
        books.insert(movedBook, at: destinationIndexPath.row)
        list.books = NSOrderedSet(array: books)
        list.managedObjectContext!.saveAndLogIfErrored()

        // Reneable change notification updates. Since we could be running this code in either of a diffable or legacy data source,
        // with corresponding diffable or legacy data provider, we need to do some verbose type checks. It isn't trivial to expose
        // a generic property which works in all cases.
        if #available(iOS 13.0, *), let diffableSetDataProvider = setDataProvider as? DiffableListBookSetDataProvider,
            let diffableDataSource = self as? ListBookDiffableDataSource {
            diffableSetDataProvider.dataSource = diffableDataSource
        } else if let legacySetDataProvider = setDataProvider as? LegacyListBookSetDataProvider, let legacyDataSource = self as? ListBookLegacyDataSource {
            legacySetDataProvider.dataSource = legacyDataSource
        } else {
            preconditionFailure()
        }
        UserEngagement.logEvent(.reorderList)

        // Delay slightly so that the UI update doesn't interfere with the animation of the row reorder completing.
        // This is quite ugly code, but leads to a less ugly UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [unowned self] in
            self.updateData(animate: false)
        }
    }
}

@available(iOS 13.0, *)
final class ListBookDiffableDataSource: EmptyDetectingTableDiffableDataSource<String, NSManagedObjectID>, ResultsControllerSnapshotGeneratorDelegate, ListBookDataSource {
    typealias SectionType = String

    var dataProvider: DiffableListBookDataProvider {
        get {
            wrappedDataProvider.wrappedValue
        }
        set {
            wrappedDataProvider.wrappedValue = newValue
            wrappedDataProvider.wrappedValue.dataSource = self
        }
    }
    private let wrappedDataProvider: Wrapped<DiffableListBookDataProvider>
    let list: List
    let searchController: UISearchController
    let onContentChanged: () -> Void
    var controllerDataProvider: ListBookControllerDataProvider? { dataProvider as? ListBookControllerDataProvider }
    var setDataProvider: ListBookSetDataProvider? { dataProvider as? ListBookSetDataProvider }

    init(_ tableView: UITableView, list: List, dataProvider: DiffableListBookDataProvider, searchController: UISearchController, onContentChanged: @escaping () -> Void) {
        // This wrapping business gets around the inabiliy to refer to self in the closure passed to super.init.
        // We need to refer to the data provider which self will have at the time the closure is run. To achieve this,
        // create a simple wrapping object: this reference stays the same, but _its_ reference can change later on.
        let wrappedDataProvider = Wrapped(dataProvider)
        self.wrappedDataProvider = wrappedDataProvider

        self.searchController = searchController
        self.list = list
        self.onContentChanged = onContentChanged
        super.init(tableView: tableView) { _, indexPath, _ in
            let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
            let book = wrappedDataProvider.wrappedValue.getBook(at: indexPath)
            cell.configureFrom(book, includeReadDates: false)
            return cell
        }

        self.dataProvider.dataSource = self
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow()
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
    }

    func getBook(at indexPath: IndexPath) -> Book {
        return dataProvider.getBook(at: indexPath)
    }

    func updateData(animate: Bool) {
        apply(dataProvider.snapshot(), animatingDifferences: animate)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeProducingSnapshot snapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>, withChangedObjects changedObjects: [NSManagedObjectID]) {
        onContentChanged()
        apply(snapshot, animatingDifferences: true)
    }
}

@available(iOS, obsoleted: 13.0)
final class ListBookLegacyDataSource: LegacyEmptyDetectingTableDataSource, NSFetchedResultsControllerDelegate, ListBookDataSource {

    var dataProvider: LegacyListBookDataProvider {
        didSet {
            dataProvider.dataSource = self
            configureChangeMonitoring()
        }
    }
    var controllerDataProvider: ListBookControllerDataProvider? { dataProvider as? ListBookControllerDataProvider }
    var setDataProvider: ListBookSetDataProvider? { dataProvider as? ListBookSetDataProvider }
    let list: List
    let onContentChanged: () -> Void
    let searchController: UISearchController

    init(_ tableView: UITableView, list: List, dataProvider: LegacyListBookDataProvider, searchController: UISearchController, onContentChanged: @escaping () -> Void) {
        self.list = list
        self.dataProvider = dataProvider
        self.searchController = searchController
        self.onContentChanged = onContentChanged
        super.init(tableView)

        self.dataProvider.dataSource = self
        configureChangeMonitoring()
    }

    private func configureChangeMonitoring() {
        if let controllerProvider = dataProvider as? LegacyListBookControllerDataProvider {
            controllerProvider.controller.delegate = self
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
        let book = dataProvider.getBook(at: indexPath)
        cell.initialise(withTheme: UserDefaults.standard[.theme])
        cell.configureFrom(book, includeReadDates: false)
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func getBook(at indexPath: IndexPath) -> Book {
        return dataProvider.getBook(at: indexPath)
    }

    override func sectionCount(in tableView: UITableView) -> Int {
        return dataProvider.sectionCount()
    }

    override func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        return dataProvider.rowCount(in: section)
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow()
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
    }

    func updateData(animate: Bool) {
       // Brute force approach for pre-iOS 13
       tableView.reloadData()
    }

    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        onContentChanged()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}
