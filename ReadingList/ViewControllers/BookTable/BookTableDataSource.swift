import ReadingList_Foundation
import CoreData

protocol BookTableDataSourceCommon: UITableViewEmptyDetectingDataSource, NSFetchedResultsControllerDelegate {
    var sortManager: SortManager<Book> { get }
    var searchController: UISearchController { get }
    var context: NSManagedObjectContext { get }

    func updateData(animate: Bool)
    func replaceControllers(_ controllers: [(BookReadState, NSFetchedResultsController<Book>)])
    func sectionCount() -> Int
    func rowCount(in section: Int) -> Int
    func readState(forIndex indexPath: IndexPath) -> BookReadState
    func object(at indexPath: IndexPath) -> Book
    func indexPath(forObject object: Book) -> IndexPath?
    func performFetch() throws
}

extension BookTableDataSourceCommon {
    func canMoveRow(at indexPath: IndexPath) -> Bool {
        // Disable reorderng when searching, or when the sort order is not custom
        guard !searchController.hasActiveSearchTerms else { return false }
        let readState = self.readState(forIndex: indexPath)
        guard UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)] == .custom else { return false }

        // We can reorder the books if there are more than one
        return rowCount(in: indexPath.section) > 1
    }

    func moveRow(at sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // We should only have movement within a section
        guard sourceIndexPath.section == destinationIndexPath.section else { return }
        let readState = self.readState(forIndex: sourceIndexPath)
        guard UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)] == .custom else { return }

        sortManager.move(objectAt: sourceIndexPath, to: destinationIndexPath)
        context.saveAndLogIfErrored()
        try! performFetch()
    }
}

@available(iOS, obsoleted: 13.0)
final class BookTableDataSourceLegacy: LegacyEmptyDetectingTableDataSource, BookTableDataSourceCommon {
    var resultsController: CompoundFetchedResultsController<Book>
    let sortManager: SortManager<Book>
    let searchController: UISearchController
    let context = PersistentStoreManager.container.viewContext

    init(_ tableView: UITableView, resultsControllers: [NSFetchedResultsController<Book>], sortManager: SortManager<Book>, searchController: UISearchController) {
        self.resultsController = CompoundFetchedResultsController(controllers: resultsControllers)
        self.sortManager = sortManager
        self.searchController = searchController
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

    func replaceControllers(_ controllers: [(BookReadState, NSFetchedResultsController<Book>)]) {
        self.resultsController = CompoundFetchedResultsController(controllers: controllers.map { $0.1 })
        self.resultsController.delegate = self
    }

    func performFetch() throws {
        try resultsController.performFetch()
    }

    func indexPath(forObject object: Book) -> IndexPath? {
        return resultsController.indexPath(forObject: object)
    }

    func readState(forIndex indexPath: IndexPath) -> BookReadState {
        let sectionName = resultsController.sections![indexPath.section].name
        guard let sectionNameInt = Int16(sectionName), let readState = BookReadState(rawValue: sectionNameInt) else {
            preconditionFailure("Unexpected section name \"\(sectionName)\"")
        }
        return readState
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
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}

/**
 In order to have the various different fetched results controller delegates work independantly, we need to be able to identify a book by both its object ID and the section
 (i.e. read state) it is in. This is because we may process a notification of the Insert into section A prior to the deletion from section B - and any subsequent call to delete
 a specific item identifier will delete it everywhere in the table.
*/
struct BookIdentifier: Hashable {
    let objectId: NSManagedObjectID
    let readState: BookReadState
}

extension Book {
    var dataSourceIdentifier: BookIdentifier {
        assert(!objectID.isTemporaryID)
        return BookIdentifier(objectId: objectID, readState: readState)
    }
}

@available(iOS 13.0, *)
final class BookTableDataSource: EmptyDetectingTableDiffableDataSource<BookReadState, BookIdentifier>, BookTableDataSourceCommon {
    let context: NSManagedObjectContext
    var controllers: [(BookReadState, NSFetchedResultsController<Book>)]
    let onChange: () -> Void
    let sortManager: SortManager<Book>
    let searchController: UISearchController

    init(_ tableView: UITableView, context: NSManagedObjectContext, controllers: [(BookReadState, NSFetchedResultsController<Book>)], sortManager: SortManager<Book>, searchController: UISearchController, onChange: @escaping () -> Void) {
        self.controllers = controllers
        self.context = context
        self.sortManager = sortManager
        self.searchController = searchController
        self.onChange = onChange
        super.init(tableView: tableView) { _, indexPath, itemId in
            let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
            let book = context.object(with: itemId.objectId) as! Book
            cell.configureFrom(book)
            return cell
        }

        // Handle change notifications going forward
        setControllerDelegates(self)
    }

    func replaceControllers(_ controllers: [(BookReadState, NSFetchedResultsController<Book>)]) {
        self.controllers = controllers
        setControllerDelegates(self)
    }

    private func setControllerDelegates(_ delegate: NSFetchedResultsControllerDelegate?) {
        for controller in controllers {
            controller.1.delegate = delegate
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

    func updateData(animate: Bool) {
        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<BookReadState, BookIdentifier>()
        for (state, controller) in controllers {
            guard let sections = controller.sections else { preconditionFailure("No fetch has been perfomed yet") }
            assert(sections.count == 1)
            // Skip the section if there are no objects
            guard let firstSection = sections.first, firstSection.numberOfObjects > 0 else { continue }
            diffableDataSourceSnapshot.appendSections([state])
            diffableDataSourceSnapshot.appendItems(controller.fetchedObjects!.map { BookIdentifier(objectId: $0.objectID, readState: state) }, toSection: state)
        }
        apply(diffableDataSourceSnapshot, animatingDifferences: animate)
    }

    func object(at indexPath: IndexPath) -> Book {
        guard let itemId = itemIdentifier(for: indexPath) else { preconditionFailure() }
        return context.object(with: itemId.objectId) as! Book
    }

    func readState(forIndex indexPath: IndexPath) -> BookReadState {
        guard let item = itemIdentifier(for: indexPath), let section = snapshot().sectionIdentifier(containingItem: item) else {
            preconditionFailure()
        }
        return section
    }

    func performFetch() throws {
        for controller in controllers {
            try controller.1.performFetch()
        }
    }

    func indexPath(forObject object: Book) -> IndexPath? {
        return indexPath(for: object.dataSourceIdentifier)
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow(at: indexPath)
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        setControllerDelegates(nil)
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
        setControllerDelegates(self)
        // Delay half a second so that the UI update doesn't interfere with the animation of the row reorder completing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [unowned self] in
            self.updateData(animate: false)
        }
    }

    // MARK: NSFetchedResultsControllerDelegate implementation

    // We cannot keep track of the changes in a DiffableDataSourceSnapshot unfortunately, as the changes may come in in an order
    // which we do not support. For example, it may notify us of new inserts at large indices before inserts at smaller indices.
    // Hence, accumulate all the changes here; when they are all loaded, we will build a new snapshot.
    private var changeProcessingSnapshot: NSDiffableDataSourceSnapshot<BookReadState, BookIdentifier>!
    private var transientChanges = [CollectionDifference<BookIdentifier>.Change]()
    private var updatedObjects = Set<BookIdentifier>()

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updatedObjects = Set<BookIdentifier>()
        transientChanges = []
        changeProcessingSnapshot = snapshot()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard let readStateIndex = controllers.map({ $0.1 }).firstIndex(of: controller as! NSFetchedResultsController<Book>) else { preconditionFailure() }
        let relevantReadState = controllers[readStateIndex].0

        // We shouldn't ever have any change refer to any section other than the first - since they all think they are
        // the first section!
        assert(indexPath?.section == nil || newIndexPath?.section == nil || indexPath?.section == 0 || newIndexPath?.section == 0)

        let changedObjectId = BookIdentifier(objectId: (anObject as! NSManagedObject).objectID, readState: relevantReadState)

        switch type {
        case .insert:
            guard let newIndex = newIndexPath?.row else { preconditionFailure() }
            transientChanges.append(.insert(offset: newIndex, element: changedObjectId, associatedWith: nil))
        case .move:
            guard let oldIndex = indexPath?.row, let newIndex = newIndexPath?.row else { preconditionFailure() }
            updatedObjects.insert(changedObjectId)
            transientChanges.append(.insert(offset: newIndex, element: changedObjectId, associatedWith: oldIndex))
            transientChanges.append(.remove(offset: oldIndex, element: changedObjectId, associatedWith: newIndex))
        case .update:
            updatedObjects.insert(changedObjectId)
        case .delete:
            guard let oldIndex = indexPath?.row else { preconditionFailure() }
            transientChanges.append(.remove(offset: oldIndex, element: changedObjectId, associatedWith: nil))
        @unknown default:
            assertionFailure("Unhandled \(NSFetchedResultsChangeType.self) \(type)")
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let collectionDifference = CollectionDifference(transientChanges) else {
            preconditionFailure("Unable to create a collection difference from the changes \(transientChanges)")
        }

        guard let relevantControllerAndReadState = controllers.first(where: { $0.1 == controller }) else { preconditionFailure() }
        let relevantReadState = relevantControllerAndReadState.0
        guard let readStateIndex = controllers.firstIndex(where: { $0.0 == relevantReadState }) else { preconditionFailure() }

        for change in collectionDifference {
            switch change {
            case .insert(let offset, let changedObjectId, _):
                // First, if the section into which this identifier is to be inserted does not yet exist, create it. We need to insert it
                // at the correct position, so find the preceeding or succeeding section which does exist (if any) as a positional reference.
                if !changeProcessingSnapshot.sectionIdentifiers.contains(relevantReadState) {
                    if let preceedingSection = controllers.prefix(upTo: readStateIndex).reversed().first(where: { !$0.1.fetchedObjects!.isEmpty })?.0 {
                        changeProcessingSnapshot.insertSections([relevantReadState], afterSection: preceedingSection)
                    } else if let suceedingSection = controllers.suffix(from: controllers.index(after: readStateIndex)).first(where: { !$0.1.fetchedObjects!.isEmpty })?.0 {
                        changeProcessingSnapshot.insertSections([relevantReadState], beforeSection: suceedingSection)
                    } else {
                        changeProcessingSnapshot.appendSections([relevantReadState])
                    }
                }

                let items = changeProcessingSnapshot.itemIdentifiers(inSection: relevantReadState)
                if offset == items.endIndex || items.isEmpty {
                    changeProcessingSnapshot.appendItems([changedObjectId], toSection: relevantReadState)
                } else {
                    changeProcessingSnapshot.insertItems([changedObjectId], beforeItem: items[offset])
                }
            case .remove(offset: _, element: let changedObjectId, associatedWith: _):
                if changeProcessingSnapshot.itemIdentifiers(inSection: relevantReadState) == [changedObjectId] {
                    changeProcessingSnapshot.deleteSections([relevantReadState])
                } else {
                    changeProcessingSnapshot.deleteItems([changedObjectId])
                }
            }
        }

        changeProcessingSnapshot.reloadItems(Array(updatedObjects))

        apply(changeProcessingSnapshot)
        onChange()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {

        // We shouldn't ever be here since our controllers don't have section keypaths. All section management is done instead
        // via the item-level delegate method above.
        assert(false)
    }
}
