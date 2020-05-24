import ReadingList_Foundation
import CoreData

protocol BookTableDataSourceCommon: UITableViewEmptyDetectingDataSource, NSFetchedResultsControllerDelegate {
    var sortManager: SortManager<Book> { get }
    var searchController: UISearchController { get }
    var context: NSManagedObjectContext { get }

    func updateData(animate: Bool)
    func replaceControllers(_ controllers: [NSFetchedResultsController<Book>])
    func sectionCount() -> Int
    func rowCount(in section: Int) -> Int
    func readState(forSection section: Int) -> BookReadState
    func object(at indexPath: IndexPath) -> Book
    func indexPath(forObject object: Book) -> IndexPath?
    func performFetch() throws
}

extension BookTableDataSourceCommon {
    func readState(forSectionName sectionName: String) -> BookReadState {
        guard let sectionNameInt = Int16(sectionName), let readState = BookReadState(rawValue: sectionNameInt) else {
            preconditionFailure("Unexpected section name \"\(sectionName)\"")
        }
        return readState
    }

    func canMoveRow(at indexPath: IndexPath) -> Bool {
        // Disable reorderng when searching, or when the sort order is not custom
        guard !searchController.hasActiveSearchTerms else { return false }
        let readState = self.readState(forSection: indexPath.section)
        guard UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)] == .custom else { return false }

        // We can reorder the books if there are more than one
        return rowCount(in: indexPath.section) > 1
    }

    func moveRow(at sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // We should only have movement within a section
        guard sourceIndexPath.section == destinationIndexPath.section else { return }
        let readState = self.readState(forSection: sourceIndexPath.section)
        guard UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)] == .custom else { return }

        sortManager.move(objectAt: sourceIndexPath, to: destinationIndexPath)
        context.saveAndLogIfErrored()
        try! performFetch()
    }
}

@available(iOS, obsoleted: 13.0)
final class BookTableLegacyDataSource: LegacyEmptyDetectingTableDataSource, BookTableDataSourceCommon {
    var resultsController: CompoundFetchedResultsController<Book>
    let sortManager: SortManager<Book>
    let searchController: UISearchController
    let context = PersistentStoreManager.container.viewContext
    let onChange: () -> Void

    init(_ tableView: UITableView, resultsControllers: [NSFetchedResultsController<Book>], sortManager: SortManager<Book>, searchController: UISearchController, onChange: @escaping () -> Void) {
        self.resultsController = CompoundFetchedResultsController(controllers: resultsControllers)
        self.sortManager = sortManager
        self.searchController = searchController
        self.onChange = onChange
        super.init(tableView)
        self.resultsController.delegate = self
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
        let book = resultsController.object(at: indexPath)
        cell.configureFrom(book)
        cell.initialise(withTheme: UserDefaults.standard[.theme])
        return cell
    }

    func replaceControllers(_ controllers: [NSFetchedResultsController<Book>]) {
        self.resultsController = CompoundFetchedResultsController(controllers: controllers)
        self.resultsController.delegate = self
    }

    func performFetch() throws {
        try resultsController.performFetch()
    }

    func indexPath(forObject object: Book) -> IndexPath? {
        return resultsController.indexPath(forObject: object)
    }

    func readState(forSection section: Int) -> BookReadState {
        return readState(forSectionName: resultsController.sections![section].name)
    }

    func rowCount(in section: Int) -> Int {
        return resultsController.sections![section].numberOfObjects
    }

    func sectionCount() -> Int {
        return resultsController.sections!.count
    }

    override func sectionCount(in tableView: UITableView) -> Int {
        return sectionCount()
    }

    override func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        return rowCount(in: section)
    }

    func updateData(animate: Bool) {
        tableView.reloadData()
    }

    func object(at indexPath: IndexPath) -> Book {
        return resultsController.object(at: indexPath)
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow(at: indexPath)
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        resultsController.delegate = nil
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
        resultsController.delegate = self
    }

    // MARK: NSFetchedResultsControllerDelegate implementation

    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        onChange()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}

@available(iOS 13.0, *)
final class BookTableDiffableDataSource: EmptyDetectingTableDiffableDataSource<BookReadState, NSManagedObjectID>, BookTableDataSourceCommon {
    let context: NSManagedObjectContext
    var controllers: [NSFetchedResultsController<Book>]
    let onChange: () -> Void
    let sortManager: SortManager<Book>
    let searchController: UISearchController

    var changeProcessors = [ResultsControllerSnapshotGenerator<BookTableDiffableDataSource>]()
    var cachedSnapshots = [NSFetchedResultsController<Book>: NSDiffableDataSourceSnapshot<BookReadState, NSManagedObjectID>]()

    init(_ tableView: UITableView, context: NSManagedObjectContext, controllers: [NSFetchedResultsController<Book>], sortManager: SortManager<Book>, searchController: UISearchController, onChange: @escaping () -> Void) {
        self.controllers = controllers
        self.context = context
        self.sortManager = sortManager
        self.searchController = searchController
        self.onChange = onChange

        super.init(tableView: tableView) { _, indexPath, itemId in
            let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
            let book = context.object(with: itemId) as! Book
            cell.configureFrom(book)
            return cell
        }

        replaceControllers(controllers)
    }

    func replaceControllers(_ controllers: [NSFetchedResultsController<Book>]) {
        self.controllers = controllers
        for controller in controllers {
            let changeProcessor = ResultsControllerSnapshotGenerator<BookTableDiffableDataSource>(mapSection: self.readState(forSectionName:)) { [unowned self] in
                self.cachedSnapshots[controller]!
            }
            controller.delegate = changeProcessor.controllerDelegate
            changeProcessors.append(changeProcessor)
        }
        setChangeProcessorDelegates(toSelf: true)
    }

    private func setChangeProcessorDelegates(toSelf setToSelf: Bool) {
        for processor in changeProcessors {
            processor.delegate = setToSelf ? self : nil
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func rowCount(in section: Int) -> Int {
        let snapshot = self.snapshot()
        return snapshot.numberOfItems(inSection: snapshot.sectionIdentifiers[section])
    }

    func sectionCount() -> Int {
        return snapshot().sectionIdentifiers.count
    }

    func loadSnapshotFromCache() -> NSDiffableDataSourceSnapshot<BookReadState, NSManagedObjectID> {
        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<BookReadState, NSManagedObjectID>()
        diffableDataSourceSnapshot.append(controllers.map { cachedSnapshots[$0]! })
        return diffableDataSourceSnapshot
    }

    func updateData(animate: Bool) {
        for controller in controllers {
            cachedSnapshots[controller] = NSDiffableDataSourceSnapshot<BookReadState, NSManagedObjectID>(controller as! NSFetchedResultsController<NSFetchRequestResult>, mappingSections: self.readState(forSectionName:))
        }
        let snapshot = loadSnapshotFromCache()
        apply(snapshot, animatingDifferences: animate)
    }

    func object(at indexPath: IndexPath) -> Book {
        guard let itemId = itemIdentifier(for: indexPath) else { preconditionFailure() }
        return context.object(with: itemId) as! Book
    }

    func readState(forSection section: Int) -> BookReadState {
        return snapshot().sectionIdentifiers[section]
    }

    func performFetch() throws {
        for controller in controllers {
            try controller.performFetch()
        }
    }

    func indexPath(forObject object: Book) -> IndexPath? {
        return indexPath(for: object.objectID)
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow(at: indexPath)
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        setChangeProcessorDelegates(toSelf: false)
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
        setChangeProcessorDelegates(toSelf: true)
        // Delay slightly so that the UI update doesn't interfere with the animation of the row reorder completing.
        // This is quite ugly code, but leads to a less ugly UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [unowned self] in
            self.updateData(animate: false)
        }
    }
}

@available(iOS 13.0, *)
extension BookTableDiffableDataSource: ResultsControllerSnapshotGeneratorDelegate {
    typealias SectionType = BookReadState

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeProducingSnapshot snapshot: NSDiffableDataSourceSnapshot<BookReadState, NSManagedObjectID>, withChangedObjects changedObjects: [NSManagedObjectID]) {
        // Store the new snapshot in the cache
        cachedSnapshots[controller as! NSFetchedResultsController<Book>] = snapshot

        // Then build a new snapshot by merging together all the cached ones. We need to reload the items as indicated,
        // as building a new snapshot loses that information: it does not need to be publicly exposed.
        var snapshot = loadSnapshotFromCache()
        snapshot.reloadValidItems(changedObjects)
        apply(snapshot, animatingDifferences: true)
        self.onChange()
    }
}
