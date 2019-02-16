import Foundation
import UIKit
import CoreData
import DZNEmptyDataSet

class ListBookTable: UITableViewController {

    var list: List!
    var cachedListNames: [String]!
    var ignoreNotifications = false
    var controller: NSFetchedResultsController<Book>?

    private var listNameField: UITextField? {
        return navigationItem.titleView as? UITextField
    }

    private var listNameFieldDefaultText: String {
        return "\(list.name)⌄"
    }

    @IBOutlet private weak var sortButton: UIBarButtonItem!
    @IBOutlet private weak var editButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UINib(BookTableViewCell.self), forCellReuseIdentifier: String(describing: BookTableViewCell.self))

        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
        navigationItem.title = list.name

        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(managedObjectContextChanged(_:)), name: .NSManagedObjectContextObjectsDidChange,
                                               object: list.managedObjectContext!)
        generateResultsControllerIfNecessary()
        monitorThemeSetting()
    }

    override func initialise(withTheme theme: Theme) {
        super.initialise(withTheme: theme)
        if let listNameField = listNameField {
            listNameField.textColor = theme.titleTextColor
        }
    }

    private func listTextField() -> UITextField {
        guard let navigationBar = navigationController?.navigationBar else { preconditionFailure() }
        let textField = UITextField(frame: navigationBar.frame.inset(by: UIEdgeInsets(top: 0, left: 115, bottom: 0, right: 115)))
        textField.text = listNameFieldDefaultText
        textField.textAlignment = .center
        textField.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        textField.textColor = UserDefaults.standard[.theme].titleTextColor
        textField.enablesReturnKeyAutomatically = true
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(self.configureBarButtons), for: .editingChanged)
        return textField
    }

    @IBAction private func sortTapped(_ sender: UIBarButtonItem) {
        let alert = UIAlertController(title: "Choose Order", message: nil, preferredStyle: .actionSheet)
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = sender
        }
        for listOrder in BookSort.allCases {
            let title = list.order == listOrder ? "  \(listOrder) ✓" : listOrder.description
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                if self.list.order != listOrder {
                    self.list.order = listOrder
                    self.list.managedObjectContext!.saveAndLogIfErrored()
                    self.sortOrderChanged()
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @IBAction private func editTapped(_ sender: UIBarButtonItem) {
        setEditing(!isEditing, animated: true)
        configureBarButtons()
    }

    private func canUpdateListName(to name: String) -> Bool {
        guard !name.isEmptyOrWhitespace else { return false }
        return name == list.name || !cachedListNames.contains(name)
    }

    @discardableResult private func tryUpdateListName(to name: String) -> Bool {
        if canUpdateListName(to: name) {
            list.name = name
            list.managedObjectContext!.saveAndLogIfErrored()
            return true
        } else {
            return false
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        if !editing, let listNameField = listNameField, listNameField.isEditing {
            if let proposedName = listNameField.text {
                tryUpdateListName(to: proposedName)
            }
            listNameField.endEditing(true)
        }
        toggleTitleView()
    }

    private func toggleTitleView() {
        if navigationItem.titleView != nil {
            navigationItem.titleView = nil
            navigationItem.title = list.name
        } else {
            navigationItem.titleView = listTextField()
            navigationItem.title = nil
        }
    }

    @objc private func configureBarButtons() {
        sortButton.isEnabled = list.books.count != 0 && !isEditing //swiftlint:disable:this empty_count
        editButton.style = isEditing ? .done : .plain
        editButton.title = isEditing ? "Done" : "Edit"
        editButton.isEnabled = {
            if let listNameField = listNameField {
                if !listNameField.isEditing { return true }
                if let newName = listNameField.text, canUpdateListName(to: newName) { return true }
                return false
            }
            return true
        }()
    }

    private func generateResultsControllerIfNecessary() {
        if list.order == .custom {
            // Custom order is determined by the ordering within the ordered relationship, and we can't
            // use make the controller sort by that ordering.
            controller = nil
            return
        }

        let fetch = NSManagedObject.fetchRequest(Book.self, batch: 50)
        fetch.predicate = NSPredicate(format: "%@ IN %K", list, #keyPath(Book.lists))
        fetch.sortDescriptors = list.order.sortDescriptors
        controller = NSFetchedResultsController(fetchRequest: fetch, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        try! controller!.performFetch()
        controller!.delegate = tableView
    }

    private func sortOrderChanged() {
        generateResultsControllerIfNecessary()
        tableView.reloadData()
        // Put the top row at the "middle", so that the top row is not right up at the top of the table
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: false)
    }

    @objc private func managedObjectContextChanged(_ notification: Notification) {
        guard !ignoreNotifications else { return }
        guard let userInfo = notification.userInfo else { return }

        if (userInfo[NSDeletedObjectsKey] as? NSSet)?.contains(list) == true {
            // If the list was deleted, pop back. This can't happen through any normal means at the moment.
            navigationController?.popViewController(animated: false)
            return
        }

        // Repopulate the list names cache
        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)

        // We are not using an NSFetchResultsControllerDelegate if the sort order is manual, so reload the table data.
        if controller?.delegate == nil {
            tableView.reloadData()
        }
    }

    private func ignoringSaveNotifications(_ block: () -> Void) {
        ignoreNotifications = true
        block()
        ignoreNotifications = false
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section == 0 else { return 0 }
        if let controller = controller {
            return controller.sections![0].numberOfObjects
        } else {
            return list.books.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: String(describing: BookTableViewCell.self), for: indexPath) as! BookTableViewCell

        let book: Book
        if let controller = controller {
            book = controller.object(at: indexPath)
        } else {
            book = list.books.object(at: indexPath.row) as! Book
        }
        cell.initialise(withTheme: UserDefaults.standard[.theme])
        cell.configureFrom(book, includeReadDates: false)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performSegue(withIdentifier: "showDetail", sender: indexPath)
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return !tableView.isEditing
    }

    private func removeBook(at indexPath: IndexPath) {
        let bookToRemove: Book
        if let controller = controller {
            bookToRemove = controller.object(at: indexPath)
        } else {
            bookToRemove = list.books[indexPath.row] as! Book
        }
        list.removeBooks(NSSet(object: bookToRemove))
        list.managedObjectContext!.saveAndLogIfErrored()
        UserEngagement.logEvent(.removeBookFromList)
    }

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [UITableViewRowAction(style: .destructive, title: "Remove") { _, indexPath in
            self.ignoringSaveNotifications {
                self.removeBook(at: indexPath)
                if self.controller?.delegate == nil {
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                }
            }
            self.tableView.reloadEmptyDataSet()
        }]
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return list.order == .custom && list.books.count > 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath != destinationIndexPath else { return }
        ignoringSaveNotifications {
            var books = list.books.map { $0 as! Book }
            let movedBook = books.remove(at: sourceIndexPath.row)
            books.insert(movedBook, at: destinationIndexPath.row)
            list.books = NSOrderedSet(array: books)
            list.managedObjectContext!.saveAndLogIfErrored()
        }
        UserEngagement.logEvent(.reorederList)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let detailsViewController = (segue.destination as? UINavigationController)?.topViewController as? BookDetails {
            guard let senderIndex = sender as? IndexPath else { preconditionFailure() }
            let book: Book
            if let controller = controller {
                book = controller.object(at: senderIndex)
            } else {
                book = list.books.object(at: senderIndex.row) as! Book
            }
            detailsViewController.book = book
        }
    }
}

extension ListBookTable: DZNEmptyDataSetSource {
    func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        return StandardEmptyDataset.title(withText: "✨ Empty List")
    }

    func description(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        return StandardEmptyDataset.description(withMarkdownText: "The list \"\(list.name)\" is currently empty.  To add a book to it, find a book and click **Add to List**.")
    }
}

extension ListBookTable: DZNEmptyDataSetDelegate {
    func emptyDataSetWillAppear(_ scrollView: UIScrollView!) {
        configureBarButtons()
    }

    func emptyDataSetDidDisappear(_ scrollView: UIScrollView!) {
        configureBarButtons()
    }
}

extension ListBookTable: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.text = list.name
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.text = listNameFieldDefaultText
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let newText = textField.text, tryUpdateListName(to: newText) else { return false }
        textField.resignFirstResponder()
        return true
    }
}
