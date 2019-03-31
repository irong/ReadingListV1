import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

class AddToExistingLists: UITableViewController {
    var resultsController: NSFetchedResultsController<List>!
    var onComplete: (() -> Void)?
    var books: Set<Book>!
    @IBOutlet private weak var addModeButton: UIBarButtonItem!
    @IBOutlet private weak var bottomBarDoneButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !books.isEmpty else { preconditionFailure() }

        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 40)
        fetchRequest.predicate = NSPredicate.or(books.map {
            NSPredicate(format: "SELF IN %@", $0.lists).not()
        })
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.sort), NSSortDescriptor(\List.name)]
        resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        resultsController.delegate = tableView
        try! resultsController.performFetch()

        monitorThemeSetting()
        navigationController?.setToolbarHidden(false, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setToolbarHidden(false, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return resultsController.sections![0].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExistingListCell", for: indexPath)
        cell.defaultInitialise(withTheme: UserDefaults.standard[.theme])

        let list = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
        cell.textLabel!.text = list.name
        cell.detailTextLabel!.text = "\(list.books.count) book\(list.books.count == 1 ? "" : "s")"

        if books.count > 1 {
            let overlapCount = getBookListOverlap(list)
            if overlapCount > 0 {
                cell.detailTextLabel!.text?.append(" (\(overlapCount) already added)")
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            configureBottomBar()
        } else {
            // Append the books to the end of the selected list
            let list = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
            list.managedObjectContext!.performAndSave {
                list.addBooks(NSOrderedSet(set: self.books))
            }
            navigationController?.dismiss(animated: true, completion: onComplete)
            UserEngagement.logEvent(.addBookToList)
        }
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isEditing else { return }
        configureBottomBar()
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        addModeButton.title = editing ? "Select Single" : "Select Many"
        if !editing {
            bottomBarDoneButton.title = "Add To Lists"
            bottomBarDoneButton.isEnabled = false
        }
    }

    @IBAction private func addModeTapped(_ sender: UIBarButtonItem) {
        setEditing(!isEditing, animated: true)
    }

    @IBAction private func addManyTapped(_ sender: Any) {
        guard let selectedRows = tableView.indexPathsForSelectedRows else { return }
        let alert = UIAlertController(title: "Add To \(selectedRows.count) List\(selectedRows.count == 1 ? "" : "s")", message: "Are you sure you want to add this book to the \(selectedRows.count) selected List\(selectedRows.count == 1 ? "" : "s")?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add To All", style: .default) { [unowned self] _ in

            let lists = selectedRows.map { self.resultsController.object(at: $0) }
            let bookSet = NSOrderedSet(set: self.books)
            PersistentStoreManager.container.viewContext.performAndSave {
                for list in lists {
                    list.addBooks(bookSet)
                }
            }
            self.navigationController?.dismiss(animated: true, completion: self.onComplete)
            UserEngagement.logEvent(.bulkAddBookToList)
        })

        present(alert, animated: true, completion: nil)
    }

    private func configureBottomBar() {
        if let selectedRows = tableView.indexPathsForSelectedRows, !selectedRows.isEmpty {
            bottomBarDoneButton.title = "Add to \(selectedRows.count) List\(selectedRows.count == 1 ? "" : "s")"
            bottomBarDoneButton.isEnabled = true
        } else {
            bottomBarDoneButton.title = "Add to Lists"
            bottomBarDoneButton.isEnabled = false
        }
    }

    private func getBookListOverlap(_ list: List) -> Int {
        let listBooks = list.books.set
        let overlapSet = (books as NSSet).mutableCopy() as! NSMutableSet
        overlapSet.intersect(listBooks)
        return overlapSet.count
    }
}
