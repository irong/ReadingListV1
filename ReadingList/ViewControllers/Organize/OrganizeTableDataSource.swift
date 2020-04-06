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

@available(iOS 13.0, *)
final class OrganizeTableViewDataSource: EmptyDetectingTableDiffableDataSource<String, NSManagedObjectID>, OrganizeTableViewDataSourceCommon {
    let sortManager: SortManager<List>
    let resultsController: NSFetchedResultsController<List>
    var changeMediator: FetchedResultsControllerChangeProcessor!

    init(tableView: UITableView, resultsController: NSFetchedResultsController<List>) {
        self.resultsController = resultsController
        self.sortManager = SortManager(tableView) {
            resultsController.object(at: $0)
        }

        super.init(tableView: tableView) { _, indexPath, _ in
            let cell = tableView.dequeueReusableCell(withIdentifier: "ListCell", for: indexPath)
            cell.configure(from: resultsController.object(at: indexPath))
            return cell
        }
        changeMediator = FetchedResultsControllerChangeProcessor { [unowned self] in
            self.snapshot()
        }
        changeMediator.delegate = self

        resultsController.delegate = changeMediator
    }

    func updateData(animate: Bool) {
        apply(resultsController.snapshot(), animatingDifferences: animate)
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

@available(iOS 13.0, *)
extension OrganizeTableViewDataSource: FetchedResultsControllerChangeProcessorDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeProducingSnapshot snapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>) {
        apply(snapshot, animatingDifferences: true)
    }
}

@available(iOS, obsoleted: 13.0)
final class OrganizeTableViewDataSourceLegacy: LegacyEmptyDetectingTableDataSource, OrganizeTableViewDataSourceCommon {
    let sortManager: SortManager<List>
    let resultsController: NSFetchedResultsController<List>

    init(_ tableView: UITableView, resultsController: NSFetchedResultsController<List>) {
        self.resultsController = resultsController
        self.sortManager = SortManager(tableView) {
            resultsController.object(at: $0)
        }
        super.init(tableView)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ListCell", for: indexPath)
        cell.configure(from: resultsController.object(at: indexPath))
        return cell
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

    func updateData(animate: Bool) {
        // Brute force approach for pre-iOS 13
        tableView.reloadData()
    }
}

@available(iOS, obsoleted: 13.0)
extension OrganizeTableViewDataSourceLegacy: NSFetchedResultsControllerDelegate {
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
