import Foundation
import CoreData
import UIKit
import ReadingList_Foundation

protocol ListBookTableDataSourceCommon: UITableViewEmptyDetectingDataSource {
    func updateData(animate: Bool)
}

enum ListBooksSource {
    case controller(NSFetchedResultsController<Book>)
    case orderedSet(NSOrderedSet)

    func bookIds() -> [NSManagedObjectID] {
        switch self {
        case .controller(let controller):
            return controller.fetchedObjects!.map(\.objectID)
        case .orderedSet(let set):
            return set.array.map { ($0 as! NSManagedObject).objectID }
        }
    }

    func isEmpty() -> Bool {
        switch self {
        case .controller(let controller):
            return controller.fetchedObjects!.isEmpty
        case .orderedSet(let set):
            return set.isEmpty
        }
    }

    func book(at indexPath: IndexPath) -> Book {
        switch self {
        case .controller(let controller):
            return controller.object(at: indexPath)
        case .orderedSet(let set):
            return set.object(at: indexPath.row) as! Book
        }
    }
}

@available(iOS 13.0, *)
final class ListBookTableDataSource: EmptyDetectingTableDiffableDataSource<String, NSManagedObjectID>, ListBookTableDataSourceCommon {
    var listBookSource: ListBooksSource {
        didSet {
            if case .controller(let controller) = listBookSource {
                controller.delegate = changeMediator
            }
        }
    }

    var changeMediator: FetchedResultsControllerChangeProcessor!

    init(_ tableView: UITableView, listBookSource: ListBooksSource) {
        self.listBookSource = listBookSource
        super.init(tableView: tableView) { _, indexPath, _ in
            let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
            let book = listBookSource.book(at: indexPath)
            cell.configureFrom(book, includeReadDates: false)
            return cell
        }

        // Set up the change mediator, which translates NSFetchedResultsControllerDelegate changes into snapshots
        changeMediator = FetchedResultsControllerChangeProcessor { [unowned self] in
            self.snapshot()
        }
        changeMediator.delegate = self

        if case .controller(let controller) = listBookSource {
            controller.delegate = changeMediator
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func updateData(animate: Bool) {
        var diffableDataSourceSnapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        switch listBookSource {
        case .controller(let controller):
            diffableDataSourceSnapshot = controller.snapshot()
        case .orderedSet(let set):
            diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<String, NSManagedObjectID>()
            if !listBookSource.isEmpty() {
                diffableDataSourceSnapshot.appendSections([""])
                diffableDataSourceSnapshot.appendItems(set.array.map { $0 as! NSManagedObject }.map(\.objectID), toSection: "")
            }
        }

        apply(diffableDataSourceSnapshot, animatingDifferences: animate)
    }

    /*
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard !searchController.isActive else { return false }
        return list.order == .listCustom && list.books.count > 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard list.order == .listCustom else { assertionFailure(); return }
        guard case .orderedSet = listBookSource! else { assertionFailure(); return }
        guard sourceIndexPath != destinationIndexPath else { return }
        ignoringSaveNotifications {
            var books = list.books.map { $0 as! Book }
            let movedBook = books.remove(at: sourceIndexPath.row)
            books.insert(movedBook, at: destinationIndexPath.row)
            list.books = NSOrderedSet(array: books)
            list.managedObjectContext!.saveAndLogIfErrored()

            // Regenerate the table source
            self.listBookSource = .orderedSet(list.books)
        }
        UserEngagement.logEvent(.reorderList)
    }*/
}

@available(iOS 13.0, *)
extension ListBookTableDataSource: FetchedResultsControllerChangeProcessorDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeProducingSnapshot snapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>) {
        apply(snapshot, animatingDifferences: true)
    }
}

@available(iOS, obsoleted: 13.0)
final class ListBookTableViewDataSourceLegacy: LegacyEmptyDetectingTableDataSource, ListBookTableDataSourceCommon {
    var listBookSource: ListBooksSource

    init(_ tableView: UITableView, listBookSource: ListBooksSource) {
        self.listBookSource = listBookSource
        super.init(tableView)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
        let book = listBookSource.book(at: indexPath)
        cell.initialise(withTheme: UserDefaults.standard[.theme])
        cell.configureFrom(book, includeReadDates: false)
        return cell
    }

    final override func sectionCount(in tableView: UITableView) -> Int {
        return listBookSource.isEmpty() ? 0 : 1
    }

    final override func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        return listBookSource.bookIds().count
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func updateData(animate: Bool) {
       // Brute force approach for pre-iOS 13
       tableView.reloadData()
    }
}

extension ListBookTableViewDataSourceLegacy: NSFetchedResultsControllerDelegate {
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
