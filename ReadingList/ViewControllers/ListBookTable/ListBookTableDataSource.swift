import Foundation
import CoreData
import UIKit
import ReadingList_Foundation

protocol ListBookDataSource: class, UITableViewEmptyDetectingDataSource {
    func updateData(animate: Bool)
    func getBook(at indexPath: IndexPath) -> Book
    var controllerDataProvider: ListBookControllerDataProvider? { get }
    var setDataProvider: ListBookSetDataProvider? { get }
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
    private let list: List
    private let searchIsActive: () -> Bool
    var controllerDataProvider: ListBookControllerDataProvider? { dataProvider as? ListBookControllerDataProvider }
    var setDataProvider: ListBookSetDataProvider? { dataProvider as? ListBookSetDataProvider }

    init(_ tableView: UITableView, list: List, dataProvider: DiffableListBookDataProvider, searchIsActive: @escaping () -> Bool) {
        // This wrapping business gets around the inabiliy to refer to self in the closure passed to super.init.
        // We need to refer to the data provider which self will have at the time the closure is run. To achieve this,
        // create a simple wrapping object: this reference stays the same, but _its_ reference can change later on.
        let wrappedDataProvider = Wrapped(dataProvider)
        self.wrappedDataProvider = wrappedDataProvider

        self.searchIsActive = searchIsActive
        self.list = list
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
        guard !searchIsActive() else { return false }
        // Lists with a custom ordering use a Set data provider
        guard let setDataProvider = dataProvider as? ListBookSetDataProvider else { return false }
        return setDataProvider.books.count > 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard !searchIsActive() else { return }
        guard sourceIndexPath != destinationIndexPath else { return }
        guard dataProvider is ListBookSetDataProvider else { return }

        // Disable change notification updates
        dataProvider.dataSource = nil

        var books = list.books.map { $0 as! Book }
        let movedBook = books.remove(at: sourceIndexPath.row)
        books.insert(movedBook, at: destinationIndexPath.row)
        list.books = NSOrderedSet(array: books)
        list.managedObjectContext!.saveAndLogIfErrored()

        // Regenerate the table source
        dataProvider.dataSource = self
        UserEngagement.logEvent(.reorderList)

        // Delay slightly so that the UI update doesn't interfere with the animation of the row reorder completing.
        // This is quite ugly code, but leads to a less ugly UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [unowned self] in
            self.updateData(animate: false)
        }
    }

    func getBook(at indexPath: IndexPath) -> Book {
        return dataProvider.getBook(at: indexPath)
    }

    func updateData(animate: Bool) {
        apply(dataProvider.snapshot(), animatingDifferences: animate)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeProducingSnapshot snapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>, withChangedObjects changedObjects: [NSManagedObjectID]) {
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

    init(_ tableView: UITableView, dataProvider: LegacyListBookDataProvider) {
        self.dataProvider = dataProvider
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

    func updateData(animate: Bool) {
       // Brute force approach for pre-iOS 13
       tableView.reloadData()
    }

    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}
