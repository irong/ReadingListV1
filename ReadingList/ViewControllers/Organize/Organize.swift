import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

extension List: Sortable {
    public var sortIndex: Int32 {
        get { return sort }
        set(newValue) { sort = newValue }
    }
}

extension UITableViewCell {
    func configure(from list: List) {
        textLabel!.text = list.name
        detailTextLabel!.text = "\(list.books.count) book\(list.books.count == 1 ? "" : "s")"
        if #available(iOS 13.0, *) { } else {
            defaultInitialise(withTheme: UserDefaults.standard[.theme])
        }
    }
}

class Organize: UITableViewController {

    var resultsController: NSFetchedResultsController<List>!
    var searchController: UISearchController!
    var dataSource: OrganizeTableViewDataSourceCommon!
    var emptyDataSetManager: OrganizeEmptyDataSetManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = true

        tableView.register(BookTableHeader.self)

        searchController = UISearchController(filterPlaceholderText: "Your Lists")
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        navigationItem.searchController = searchController

        resultsController = buildResultsController()

        if #available(iOS 13.0, *) {
            dataSource = OrganizeTableViewDataSource(tableView: tableView, resultsController: resultsController)
        } else {
            dataSource = OrganizeTableViewDataSourceLegacy(tableView, resultsController: resultsController)
        }

        emptyDataSetManager = OrganizeEmptyDataSetManager(tableView: tableView, navigationBar: navigationController?.navigationBar, navigationItem: navigationItem, searchController: searchController) { [unowned self] isEmpty in
            self.navigationItem.leftBarButtonItem = isEmpty ? nil : self.editButtonItem
        }
        dataSource.emptyDetectionDelegate = emptyDataSetManager

        try! resultsController.performFetch()
        dataSource.updateData(animate: false)

        NotificationCenter.default.addObserver(self, selector: #selector(refetch), name: .PersistentStoreBatchOperationOccurred, object: nil)

        monitorThemeSetting()
    }

    private func buildResultsController() -> NSFetchedResultsController<List> {
        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 25)
        fetchRequest.sortDescriptors = sortDescriptors()

        return NSFetchedResultsController<List>(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
    }

    private func sortDescriptors() -> [NSSortDescriptor] {
        var sortDescriptors = [NSSortDescriptor(\List.name)]
        switch UserDefaults.standard[.listSortOrder] {
        case .custom:
            sortDescriptors.insert(NSSortDescriptor(\List.sort), at: 0)
        case .alphabetical:
            break
        }
        return sortDescriptors
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        searchController.searchBar.isEnabled = !editing
        reloadHeaders()
    }

    @objc func refetch() {
        try! resultsController.performFetch()
        dataSource.updateData(animate: true)
    }

    func onSortButtonTap(_ button: UIButton) {
        let alert = UIAlertController.selectOption(ListSortOrder.allCases, title: "Choose Order", selected: UserDefaults.standard[.listSortOrder]) { sortOrder in
            UserDefaults.standard[.listSortOrder] = sortOrder
            self.resultsController = self.buildResultsController()
            try! self.resultsController.performFetch()
            self.dataSource.updateData(animate: true)
        }
        if let popover = alert.popoverPresentationController {
            popover.sourceView = button
            popover.sourceRect = button.bounds
        }
        self.present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard !emptyDataSetManager.isShowingEmptyState else { return .leastNonzeroMagnitude }
        return BookTableHeader.height
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !emptyDataSetManager.isShowingEmptyState else { return nil }
        let header = tableView.dequeue(BookTableHeader.self)
        configureHeader(header, at: section)
        header.onSortButtonTap = self.onSortButtonTap
        return header
    }

    private func renameList(_ list: List, completion: ((Bool) -> Void)? = nil) {
        let existingListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
        let renameListAlert = TextBoxAlert(title: "Rename List", message: "Choose a new name for this list", initialValue: list.name, placeholder: "New list name", keyboardAppearance: UserDefaults.standard[.theme].keyboardAppearance, textValidator: { listName in
                guard let listName = listName, !listName.isEmptyOrWhitespace else { return false }
                return listName == list.name || !existingListNames.contains(listName)
            }, onCancel: {
                completion?(false)
            }, onOK: {
                guard let listName = $0 else { return }
                UserEngagement.logEvent(.renameList)
                list.managedObjectContext!.performAndSave {
                    list.name = listName
                }
                completion?(true)
            }
        )

        self.present(renameListAlert, animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return UISwipeActionsConfiguration(performFirstActionWithFullSwipe: false, actions: [
            UIContextualAction(style: .destructive, title: "Delete") { _, _, callback in
                self.deleteList(forRowAt: indexPath) { didDelete in
                    callback(didDelete)
                }
            },
            UIContextualAction(style: .normal, title: "Rename") { _, _, callback in
                self.setEditing(false, animated: true)
                let list = self.resultsController.object(at: indexPath)
                self.renameList(list) { didRename in
                    callback(didRename)
                }
            }
        ])
    }

    @IBAction private func addWasTapped(_ sender: UIBarButtonItem) {
        present(ManageLists.newListAlertController([]) { list in
            guard let indexPath = self.resultsController.indexPath(forObject: list) else {
                //assertionFailure()
                return
            }
            self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        }, animated: true)
    }

    func deleteList(forRowAt indexPath: IndexPath, didDelete: ((Bool) -> Void)? = nil) {
        let confirmDelete = UIAlertController(title: "Confirm delete", message: nil, preferredStyle: .actionSheet)

        confirmDelete.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.resultsController.object(at: indexPath).deleteAndSave()
            UserEngagement.logEvent(.deleteList)
            self.setEditing(false, animated: true)
            didDelete?(true)
        })
        confirmDelete.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            didDelete?(false)
        })

        confirmDelete.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
        present(confirmDelete, animated: true, completion: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let listBookTable = segue.destination as? ListBookTable {
            let list: List
            if let index = sender as? IndexPath {
                list = resultsController.object(at: index)
            } else if let cell = sender as? UITableViewCell, let index = tableView.indexPath(for: cell) {
                list = resultsController.object(at: index)
            } else { preconditionFailure() }

            listBookTable.list = list

            // If the search bar is visible on this view, then it should be visible on the presented view too to
            // prevent an animation issue from occuring (https://stackoverflow.com/a/55043782/5513562) on iOS <13.
            if #available(iOS 13.0, *) { /* issue is fixed */ } else {
                listBookTable.showSearchBarOnAppearance = !searchController.isActive && searchController.searchBar.frame.height > 0 && !list.books.isEmpty
            }
        }
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        // No segue in edit mode
        return !tableView.isEditing
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // the PreviewProvider doesn't seem to work when instantiating the ListBookTable - all the cells become really
        // big, and that persists when you open from the preview.
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                    let list = self.resultsController.object(at: indexPath)
                    self.renameList(list)
                },
                UIAction(title: "Delete", image: UIImage(systemName: "trash.fill"), attributes: .destructive) { _ in
                    self.deleteList(forRowAt: indexPath)
                }
            ])
        }
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let indexPath = configuration.identifier as? IndexPath else { return }
        animator.addAnimations {
            self.performSegue(withIdentifier: "selectList", sender: indexPath)
        }
    }
}

extension Organize: HeaderConfigurable {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int) {
        guard let header = header as? BookTableHeader else { preconditionFailure() }
        header.configure(labelText: "YOUR LISTS", enableSort: !isEditing && !searchController.isActive)
    }
}

extension Organize: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        reloadHeaders()
        // If we caused all data to be deleted while searching, the empty state view might now need to be a "no lists" view
        // rather than a "no results" view.
        emptyDataSetManager.reloadEmptyStateView()
    }

    func willPresentSearchController(_ searchController: UISearchController) {
        // The search controller is not yet active, so queue up a reload of the headers once this presentation is has started
        DispatchQueue.main.async {
            self.reloadHeaders()
        }
    }
}

extension Organize: UISearchResultsUpdating {
    func predicate(forSearchText searchText: String?) -> NSPredicate {
        if let searchText = searchText, !searchText.isEmptyOrWhitespace && searchText.trimming().count >= 2 {
            return NSPredicate(fieldName: #keyPath(List.name), containsSubstring: searchText)
        }
        return NSPredicate(boolean: true) // If we cannot filter with the search text, we should return all results
    }

    func updateSearchResults(for searchController: UISearchController) {
        let searchTextPredicate = self.predicate(forSearchText: searchController.searchBar.text)

        if resultsController.fetchRequest.predicate != searchTextPredicate {
            resultsController.fetchRequest.predicate = searchTextPredicate
            try! resultsController.performFetch()
        }
        dataSource.updateData(animate: true)
    }
}
