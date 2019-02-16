import Foundation
import UIKit
import CoreData
import DZNEmptyDataSet
import ReadingList_Foundation

class Organise: UITableViewController {

    var resultsController: NSFetchedResultsController<List>!
    var searchController: UISearchController!

    override func viewDidLoad() {
        super.viewDidLoad()

        clearsSelectionOnViewWillAppear = true

        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self

        searchController = UISearchController(filterPlaceholderText: "Your Lists")
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController

        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 25)
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.name)]
        resultsController = NSFetchedResultsController<List>(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        try! resultsController.performFetch()
        resultsController.delegate = tableView

        navigationItem.leftBarButtonItem = editButtonItem

        NotificationCenter.default.addObserver(self, selector: #selector(refetch), name: NSNotification.Name.PersistentStoreBatchOperationOccurred, object: nil)

        monitorThemeSetting()
    }

    @objc func refetch() {
        try! resultsController.performFetch()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return resultsController.sections!.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return resultsController.sections![section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ListCell", for: indexPath)
        let list = resultsController.object(at: indexPath)
        cell.textLabel!.text = list.name
        cell.detailTextLabel!.text = "\(list.books.count) book\(list.books.count == 1 ? "" : "s")"
        cell.defaultInitialise(withTheme: UserDefaults.standard[.theme])
        return cell
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return UISwipeActionsConfiguration(performFirstActionWithFullSwipe: false, actions: [
            UIContextualAction(style: .destructive, title: "Delete") { _, _, callback in
                self.deleteList(forRowAt: indexPath)
                // We never perform the deletion right-away
                callback(false)
            },
            UIContextualAction(style: .normal, title: "Rename") { _, _, callback in
                self.setEditing(false, animated: true)
                let list = self.resultsController.object(at: indexPath)

                let existingListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
                let renameListAlert = TextBoxAlertController(title: "Rename List", message: "Choose a new name for this list", initialValue: list.name, placeholder: "New list name", keyboardAppearance: UserDefaults.standard[.theme].keyboardAppearance, textValidator: { listName in
                        guard let listName = listName, !listName.isEmptyOrWhitespace else { return false }
                        return listName == list.name || !existingListNames.contains(listName)
                    }, onOK: {
                        guard let listName = $0 else { return }
                        UserEngagement.logEvent(.renameList)
                        list.managedObjectContext!.performAndSave {
                            list.name = listName
                        }
                    }
                )

                self.present(renameListAlert, animated: true)
                callback(true)
            }
        ])
    }

    @IBAction private func addWasTapped(_ sender: UIBarButtonItem) {
        present(AddToList.newListAlertController([]) { [unowned self] list in
            guard let indexPath = self.resultsController.indexPath(forObject: list) else {
                assertionFailure()
                return
            }
            self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        }, animated: true)
    }

    func deleteList(forRowAt indexPath: IndexPath) {
        let confirmDelete = UIAlertController(title: "Confirm delete", message: nil, preferredStyle: .actionSheet)

        confirmDelete.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.resultsController.object(at: indexPath).deleteAndSave()
            UserEngagement.logEvent(.deleteList)

            // When the table goes from 1 row to 0 rows in the single section, the section header remains unless the table is reloaded
            if self.tableView.numberOfRows(inSection: 0) == 0 {
                self.tableView.reloadData()
            }
        })
        confirmDelete.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        confirmDelete.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
        present(confirmDelete, animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        let listCount = resultsController.sections?[0].numberOfObjects ?? 0
        return listCount == 0 ? nil : "Your lists"
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let listBookTable = segue.destination as? ListBookTable {
            listBookTable.list = resultsController.object(at: tableView.indexPath(for: (sender as! UITableViewCell))!)
        } else {
            super.prepare(for: segue, sender: sender)
        }
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        // No segue in edit mode
        return !tableView.isEditing
    }
}

extension Organise: UISearchResultsUpdating {
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
            tableView.reloadData()
        }
    }
}

extension Organise: DZNEmptyDataSetSource {

    func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        if searchController.hasActiveSearchTerms {
            return StandardEmptyDataset.title(withText: "🔍 No Results")
        }
        return StandardEmptyDataset.title(withText: "🗂️ Organise")
    }

    func verticalOffset(forEmptyDataSet scrollView: UIScrollView!) -> CGFloat {
        return -30
    }

    func description(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        if searchController.hasActiveSearchTerms {
            return StandardEmptyDataset.description(withMarkdownText: """
                Try changing your search, or add a new list by tapping the **+** button above.
                """)
        }
        return StandardEmptyDataset.description(withMarkdownText: """
            Create your own lists to organise your books.

            To create a new list, tap the **+** button above, or tap **Add To List** when viewing a book.
            """)
    }
}

extension Organise: DZNEmptyDataSetDelegate {
    func emptyDataSetWillAppear(_ scrollView: UIScrollView!) {
        navigationItem.leftBarButtonItem = nil
        navigationItem.largeTitleDisplayMode = .never
    }

    func emptyDataSetWillDisappear(_ scrollView: UIScrollView!) {
        navigationItem.leftBarButtonItem = editButtonItem
        navigationItem.largeTitleDisplayMode = .automatic
    }
}
