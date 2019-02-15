import Foundation
import UIKit
import CoreData
import DZNEmptyDataSet
import ReadingList_Foundation

class Organise: UITableViewController {

    var resultsController: NSFetchedResultsController<List>!

    override func viewDidLoad() {
        super.viewDidLoad()

        clearsSelectionOnViewWillAppear = true

        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self

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

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [
            UITableViewRowAction(style: .destructive, title: "Delete") { _, indexPath in
                self.deleteList(forRowAt: indexPath)
            },
            UITableViewRowAction(style: .normal, title: "Rename") { _, indexPath in
                self.setEditing(false, animated: true)
                let list = self.resultsController.object(at: indexPath)

                let existingListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
                let renameListAlert = TextBoxAlertController(title: "Rename List", message: "Choose a new name for this list", initialValue: list.name, placeholder: "New list name", keyboardAppearance: UserDefaults.standard[.theme].keyboardAppearance, textValidator: { listName in
                        guard let listName = listName, !listName.isEmptyOrWhitespace else { return false }
                        return listName == list.name || !existingListNames.contains(listName)
                    }, onOK: {
                        guard let listName = $0 else { return }
                        list.managedObjectContext!.performAndSave {
                            list.name = listName
                        }
                    }
                )

                self.present(renameListAlert, animated: true)
            }
        ]
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
            self.tableView.setEditing(false, animated: true)
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

extension Organise: DZNEmptyDataSetSource {

    func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        return StandardEmptyDataset.title(withText: "🗂️ Organise")
    }

    func description(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        return StandardEmptyDataset.description(withMarkdownText: """
            Create your own lists to organise your books.

            To create a new list, tap **Add To List** when viewing a book.
            """)
    }

    func verticalOffset(forEmptyDataSet scrollView: UIScrollView!) -> CGFloat {
        // The large titles make the empty data set look weirdly low down. Adjust this,
        // by - fairly randomly - the height of the nav bar
        if navigationController!.navigationBar.prefersLargeTitles {
            return -navigationController!.navigationBar.frame.height
        } else {
            return 0
        }
    }
}

extension Organise: DZNEmptyDataSetDelegate {
    func emptyDataSetDidAppear(_ scrollView: UIScrollView!) {
        navigationItem.leftBarButtonItem = nil
    }

    func emptyDataSetDidDisappear(_ scrollView: UIScrollView!) {
        navigationItem.leftBarButtonItem = editButtonItem
    }
}
