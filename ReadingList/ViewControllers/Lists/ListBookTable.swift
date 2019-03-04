import Foundation
import UIKit
import CoreData
import DZNEmptyDataSet
import ReadingList_Foundation

class ListBookTable: UITableViewController {

    var list: List!
    var cachedListNames: [String]!
    var ignoreNotifications = false
    var controller: NSFetchedResultsController<Book>!
    var searchController: UISearchController!
    var readRelatedBooksDirectly = false

    /**
     In normal operation, what value should we set readRelatedBooksDirectly to? This is true when the list sort order is
     custom (since we cannot easily use a fetched results controller with that ordering). We may want to ignore the value
     of this in special cases (e.g. when searching).
    */
    private var shouldReadRelatedBooksDirectly: Bool {
        return list.order == .listCustom
    }

    private var listNameField: UITextField? {
        return navigationItem.titleView as? UITextField
    }

    private var listNameFieldDefaultText: String {
        return "\(list.name)⌄"
    }

    private var defaultPredicate: NSPredicate {
        return NSPredicate(format: "%@ IN %K", list, #keyPath(Book.lists))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(BookTableViewCell.self)
        tableView.register(BookTableHeader.self)

        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
        navigationItem.title = list.name
        navigationItem.rightBarButtonItem = editButtonItem

        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self

        // Build up the resultsController, even though it won't always be used. If the list's sort order is custom,
        // we will just use the ordered set of books on the list. This is because the NSFetchedResultsController delegate
        // does not behave well when the ordering is specified by the ordering in a relationship (specifically, changes
        // cause an unhandled error).
        let fetchRequest = NSManagedObject.fetchRequest(Book.self, batch: 50)
        fetchRequest.predicate = defaultPredicate
        fetchRequest.sortDescriptors = list.order.sortDescriptors
        controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        readRelatedBooksDirectly = shouldReadRelatedBooksDirectly
        if !readRelatedBooksDirectly {
            controller.delegate = tableView
            try! controller.performFetch()
        }

        searchController = UISearchController(filterPlaceholderText: "Filter List")
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController

        NotificationCenter.default.addObserver(self, selector: #selector(managedObjectContextChanged(_:)), name: .NSManagedObjectContextObjectsDidChange,
                                               object: list.managedObjectContext!)
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
        let theme = UserDefaults.standard[.theme]
        let textField = UITextField(frame: navigationBar.frame.inset(by: UIEdgeInsets(top: 0, left: 115, bottom: 0, right: 115)))
        textField.text = listNameFieldDefaultText
        textField.textAlignment = .center
        textField.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        textField.textColor = theme.titleTextColor
        textField.keyboardAppearance = theme.keyboardAppearance
        textField.enablesReturnKeyAutomatically = true
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(self.configureBarButtons), for: .editingChanged)
        return textField
    }

    private func canUpdateListName(to name: String) -> Bool {
        guard !name.isEmptyOrWhitespace else { return false }
        return name == list.name || !cachedListNames.contains(name)
    }

    @discardableResult private func tryUpdateListName(to name: String) -> Bool {
        if canUpdateListName(to: name) {
            UserEngagement.logEvent(.renameList)
            list.name = name
            list.managedObjectContext!.saveAndLogIfErrored()
            return true
        } else {
            return false
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        // If we go from editing to not editing, and we are (/were) editing the title text field, then
        // save the update (if we can), and stop editing it.
        if !editing, let listNameField = listNameField, listNameField.isEditing {
            if let proposedName = listNameField.text {
                tryUpdateListName(to: proposedName)
            }
            listNameField.endEditing(true)
        }
        configureTitleView()
        configureBarButtons()
        reloadHeaders()
        searchController.searchBar.isActive = !editing
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeue(BookTableHeader.self)
        header.presenter = self
        header.onSortChanged = sortOrderChanged
        configureHeader(header, at: section)
        return header
    }

    private func configureTitleView() {
        if isEditing {
            navigationItem.titleView = listTextField()
            navigationItem.title = nil
        } else {
            navigationItem.titleView = nil
            navigationItem.title = list.name
        }
    }

    @objc private func configureBarButtons() {
        guard let editDoneButton = navigationItem.rightBarButtonItem else { assertionFailure(); return }
        editDoneButton.isEnabled = {
            if let listNameField = listNameField {
                if !listNameField.isEditing { return true }
                if let newName = listNameField.text, canUpdateListName(to: newName) { return true }
                return false
            }
            return true
        }()
    }

    private func sortOrderChanged() {
        if searchController.isActive {
            // Belts and braces; if the sort order changes while a search is going on, just stop the search.
            searchController.isActive = false
        }

        // Keep the controller up-to-date, even if we are not using it. This might be helpful later if we start searching.
        controller.fetchRequest.sortDescriptors = list.order.sortDescriptors

        readRelatedBooksDirectly = shouldReadRelatedBooksDirectly
        if !readRelatedBooksDirectly {
            controller.delegate = tableView
            try! controller.performFetch()
        }
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

        // There are some very specific use cases where we have a resultsController but it has no delegate. In that case,
        // refetch and reload the table. If we don't have a resultsController at all, just reload the table.
        if readRelatedBooksDirectly {
            tableView.reloadData()
        } else if controller.delegate == nil {
            try! controller.performFetch()
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
        if readRelatedBooksDirectly {
            return list.books.count
        } else {
            return controller.sections![0].numberOfObjects
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)

        let book: Book
        if readRelatedBooksDirectly {
            book = list.books.object(at: indexPath.row) as! Book
        } else {
            book = controller.object(at: indexPath)
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
        if readRelatedBooksDirectly {
            bookToRemove = list.books[indexPath.row] as! Book
        } else {
            bookToRemove = controller.object(at: indexPath)
        }
        list.removeBooks(NSSet(object: bookToRemove))
        list.managedObjectContext!.saveAndLogIfErrored()
        UserEngagement.logEvent(.removeBookFromList)
    }

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [UITableViewRowAction(style: .destructive, title: "Remove") { _, indexPath in
            self.ignoringSaveNotifications {
                self.removeBook(at: indexPath)
                if self.controller.delegate == nil {
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                }
            }
            self.tableView.reloadEmptyDataSet()
        }]
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return list.order == .listCustom && list.books.count > 1
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
            if readRelatedBooksDirectly {
                book = list.books.object(at: senderIndex.row) as! Book
            } else {
                book = controller.object(at: senderIndex)
            }
            detailsViewController.book = book
        }
    }
}

extension ListBookTable: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        if let searchText = searchController.searchBar.text, !searchText.isEmptyOrWhitespace && searchText.trimming().count >= 2 {
            let newSearchPredicate = NSPredicate.wordsWithinFields(searchText, fieldNames: #keyPath(Book.title), #keyPath(Book.authorSort), "ANY \(#keyPath(Book.subjects)).name")

            // Even if we are ordering by the custom order, and so not using a results controller for normal operation, we want
            // to use a results controller to show the search results. It is correct to omit to set the delegate though, as this
            // doesn't work with our chosen sort order.
            readRelatedBooksDirectly = false
            controller.fetchRequest.predicate = NSPredicate.and([defaultPredicate, newSearchPredicate])
        } else {
            readRelatedBooksDirectly = shouldReadRelatedBooksDirectly
            controller.fetchRequest.predicate = defaultPredicate
        }

        if !readRelatedBooksDirectly {
            try! controller.performFetch()
        }
        tableView.reloadData()
    }
}

extension ListBookTable: DZNEmptyDataSetSource {
    func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        if searchController.hasActiveSearchTerms {
            return StandardEmptyDataset.title(withText: "🔍 No Results")
        }
        return StandardEmptyDataset.title(withText: "✨ Empty List")
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

extension ListBookTable: HeaderConfigurable {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int) {
        guard let header = header as? BookTableHeader else { preconditionFailure() }
        header.configure(list: list, bookCount: tableView.numberOfRows(inSection: 0))
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
