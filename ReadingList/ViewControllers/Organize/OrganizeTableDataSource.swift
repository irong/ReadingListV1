import Foundation
import ReadingList_Foundation
import UIKit
import CoreData

protocol OrganizeTableViewDataSourceCommon: UITableViewEmptyDetectingDataSource, NSFetchedResultsControllerDelegate {
    var sortManager: SortManager<List> { get }
    var resultsController: NSFetchedResultsController<List> { get }

    func updateData(animate: Bool)
}

extension OrganizeTableViewDataSourceCommon {
    func canMoveRow(at indexPath: IndexPath) -> Bool {
        guard UserDefaults.standard[.listSortOrder] == .custom else { return false }
        return resultsController.sections![0].numberOfObjects > 1
    }

    func moveRow(at sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard UserDefaults.standard[.listSortOrder] == .custom else {
            assertionFailure()
            return
        }
        sortManager.move(objectAt: sourceIndexPath, to: destinationIndexPath)
        try! resultsController.performFetch()
        PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
    }
}

enum OrganizeTableSection {
    case main
}

@available(iOS 13.0, *)
final class OrganizeTableViewDataSource: UITableViewEmptyDetectingDiffableDataSource<OrganizeTableSection, List>, OrganizeTableViewDataSourceCommon, NSFetchedResultsControllerDelegate {
    let sortManager: SortManager<List>
    let resultsController: NSFetchedResultsController<List>
    let changeAccumulator = ManagedObjectChangeAccumulator<List>()

    init(tableView: UITableView, resultsController: NSFetchedResultsController<List>) {
        self.resultsController = resultsController
        self.sortManager = SortManager(tableView) {
            resultsController.object(at: $0)
        }

        super.init(tableView: tableView) { _, indexPath, itemId in
            let cell = tableView.dequeueReusableCell(withIdentifier: "ListCell", for: indexPath)
            cell.configure(from: itemId)
            return cell
        }
    }

    private func generateAndApplySnapshot(identifiers: [List]?, animate: Bool) {
        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<OrganizeTableSection, List>()
        if let identifiers = identifiers {
            diffableDataSourceSnapshot.appendSections([.main])
            diffableDataSourceSnapshot.appendItems(identifiers, toSection: .main)
        }
        apply(diffableDataSourceSnapshot, animatingDifferences: animate)
    }

    func updateData(animate: Bool) {
        generateAndApplySnapshot(identifiers: resultsController.fetchedObjects, animate: animate)
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        changeAccumulator.clearAll()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        changeAccumulator.loadChange(changedObject: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let newSnapshot = changeAccumulator.applyChangesToSnapshot(initialSnapshot: snapshot())
        apply(newSnapshot)
    }

    final override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow(at: indexPath)
    }

    final override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
    }

    final override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

@available(iOS, obsoleted: 13.0)
final class OrganizeTableViewDataSourceLegacy: UITableViewEmptyDetectingLegacyDataSource, OrganizeTableViewDataSourceCommon, NSFetchedResultsControllerDelegate {
    let tableView: UITableView
    let sortManager: SortManager<List>
    let resultsController: NSFetchedResultsController<List>

    init(_ tableView: UITableView, resultsController: NSFetchedResultsController<List>) {
        self.tableView = tableView
        self.resultsController = resultsController
        self.sortManager = SortManager(tableView) {
            resultsController.object(at: $0)
        }
        super.init(tableView) { indexPath in
            let cell = tableView.dequeueReusableCell(withIdentifier: "ListCell", for: indexPath)
            cell.configure(from: resultsController.object(at: indexPath))
            return cell
        }
    }

    final override func sectionCount(in tableView: UITableView) -> Int {
        return resultsController.sections!.count
    }

    final override func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        return resultsController.sections![section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return canMoveRow(at: indexPath)
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let delegateReference = resultsController.delegate
        resultsController.delegate = nil
        moveRow(at: sourceIndexPath, to: destinationIndexPath)
        resultsController.delegate = delegateReference
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

    func updateData(animate: Bool) {
        // Brute force approach for pre-iOS 13
        tableView.reloadData()
    }
}
