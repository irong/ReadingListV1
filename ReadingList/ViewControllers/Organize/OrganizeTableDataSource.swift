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
enum ListSection {
    case main
}

@available(iOS 13.0, *)
final class OrganizeTableViewDataSource: UITableViewEmptyDetectingDiffableDataSource<ListSection, List>, OrganizeTableViewDataSourceCommon, NSFetchedResultsControllerDelegate {
    let sortManager: SortManager<List>
    let resultsController: NSFetchedResultsController<List>
    
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
    }
    
    func updateData(animate: Bool) {
        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<ListSection, List>()
        if resultsController.fetchedObjects?.isEmpty == false {
            diffableDataSourceSnapshot.appendSections([.main])
            diffableDataSourceSnapshot.appendItems(resultsController.fetchedObjects!)
        }
        apply(diffableDataSourceSnapshot, animatingDifferences: animate)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var newSnapshot = NSDiffableDataSourceSnapshot<ListSection, List>()
        if !snapshot.itemIdentifiers.isEmpty {
            newSnapshot.appendSections([.main])
            let listItems = snapshot.itemIdentifiers.map { PersistentStoreManager.container.viewContext.object(with: $0 as! NSManagedObjectID) as! List }
            newSnapshot.appendItems(listItems, toSection: .main)
        }
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
final class OrganizeTableViewDataSourceLegacy: UITableViewEmptyDetectingLegacyDataSource, OrganizeTableViewDataSourceCommon, UITableViewDataSourceFetchedResultsControllerDelegate {
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

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        //TODO//reloadHeaders()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
    
    func updateData(animate: Bool) {
        tableView.reloadData()
    }
}
