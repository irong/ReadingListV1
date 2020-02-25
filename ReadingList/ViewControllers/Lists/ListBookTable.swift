import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

enum ListBooksSource {
    case controller(NSFetchedResultsController<Book>)
    case orderedSet(NSOrderedSet)

    func numberOfBooks() -> Int {
        switch self {
        case .controller(let controller):
            return controller.sections![0].numberOfObjects
        case .orderedSet(let set):
            return set.count
        }
    }

    func numberOfSections() -> Int {
        switch self {
        case .controller(let controller):
            return controller.sections!.count
        case .orderedSet(let set):
            return set.isEmpty ? 0 : 1
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

class ListBookTableDataSource: SearchableEmptyStateTableViewDataSource {

    var listBookSource: ListBooksSource
    let list: List

    init(_ tableView: UITableView, searchController: UISearchController, navigationItem: UINavigationItem, list: List, listBookSource: ListBooksSource) {
        self.listBookSource = listBookSource
        self.list = list
        super.init(tableView, searchController: searchController, navigationItem: navigationItem) { indexPath in
            let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
            let book = listBookSource.book(at: indexPath)
            if #available(iOS 13.0, *) { } else {
                cell.initialise(withTheme: UserDefaults.standard[.theme])
            }
            cell.configureFrom(book, includeReadDates: false)
            return cell

        }
    }

    override func sectionCount(in tableView: UITableView) -> Int {
        return listBookSource.numberOfSections()
    }

    override func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        guard section == 0 else { assertionFailure(); return 0 }
        return listBookSource.numberOfBooks()
    }

    override func titleForNonSearchEmptyState() -> String {
        return "✨ Empty List"
    }

    override func textForSearchEmptyState() -> NSAttributedString {
        return NSAttributedString(
            "Try changing your search, or add another book to this list.",
            font: emptyStateDescriptionFont)
    }

    override func textForNonSearchEmptyState() -> NSAttributedString {
        return NSMutableAttributedString(
            "The list \"\(list.name)\" is currently empty.  To add a book to it, find a book and tap ",
            font: emptyStateDescriptionFont)
            .appending("Manage Lists", font: emptyStateDescriptionBoldFont)
            .appending(".", font: emptyStateDescriptionFont)
    }
}

class ListBookTable: UITableViewController {

    var list: List!
    private var cachedListNames: [String]!
    private var ignoreNotifications = false
    private var listBookSource: ListBooksSource!

    private var searchController: UISearchController!
    private var dataSource: ListBookTableDataSource!

    /// Used to work around a animation bug, which is resolved in iOS 13, by forcing the search bar into a visible state.
    @available(iOS, obsoleted: 13.0)
    var showSearchBarOnAppearance: Bool = false {
        didSet { navigationItem.hidesSearchBarWhenScrolling = !showSearchBarOnAppearance }
    }

    private var listNameField: UITextField? {
        get { return navigationItem.titleView as? UITextField }
        set { navigationItem.titleView = newValue }
    }

    private var listNameFieldDefaultText: String {
        return "\(list.name)⌄"
    }

    private var defaultPredicate: NSPredicate {
        return NSPredicate(format: "%@ IN %K", list, #keyPath(Book.lists))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        //normalLargeTitleDisplayMode = .never

        tableView.register(BookTableViewCell.self)
        tableView.register(BookTableHeader.self)

        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
        navigationItem.title = list.name
        navigationItem.rightBarButtonItem = editButtonItem

        buildBookSource()

        searchController = UISearchController(filterPlaceholderText: "Filter List")
        searchController.searchResultsUpdater = self
        dataSource = ListBookTableDataSource(tableView, searchController: searchController, navigationItem: navigationItem, list: list, listBookSource: listBookSource)

        NotificationCenter.default.addObserver(self, selector: #selector(objectContextChanged(_:)),
                                               name: .NSManagedObjectContextObjectsDidChange,
                                               object: PersistentStoreManager.container.viewContext)
        monitorThemeSetting()
    }

    private func buildBookSource() {
        // We cannot use a fetched results controller when ordering by the underlying ordered predicate order.
        // Instead, we just use the ordered set as our source.
        if list.order == .listCustom {
            listBookSource = .orderedSet(list.books)
        } else {
            listBookSource = .controller(buildResultsController())
        }
    }

    private func buildResultsController() -> NSFetchedResultsController<Book> {
        let fetchRequest = NSManagedObject.fetchRequest(Book.self, batch: 50)
        fetchRequest.predicate = defaultPredicate
        fetchRequest.sortDescriptors = list.order.sortDescriptors
        let controller = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                    managedObjectContext: PersistentStoreManager.container.viewContext,
                                                    sectionNameKeyPath: nil, cacheName: nil)
        controller.delegate = self
        try! controller.performFetch()
        return controller
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Ensure that hidesSearchBarWhenScrolling is always true when the view appears.
        // Works in conjunction with showSearchBarOnAppearance. That only exists to work around
        // a bug which is resolved in iOS 13.
        if #available(iOS 13.0, *) { /* issue is fixed */ } else {
            navigationItem.hidesSearchBarWhenScrolling = true
        }
    }

    override func initialise(withTheme theme: Theme) {
        if #available(iOS 13.0, *) { return }
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
        if #available(iOS 13.0, *) { } else {
            let theme = UserDefaults.standard[.theme]
            textField.textColor = theme.titleTextColor
            textField.keyboardAppearance = theme.keyboardAppearance
        }
        textField.enablesReturnKeyAutomatically = true
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(self.configureNavigationItem), for: .editingChanged)
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
            if let proposedName = listNameField.text, list.name != proposedName {
                tryUpdateListName(to: proposedName)
            }
            listNameField.endEditing(true)
        }
        configureNavigationItem()
        reloadHeaders()
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 0 && tableView.numberOfRows(inSection: 0) > 0 else { return nil }
        let header = tableView.dequeue(BookTableHeader.self)
        header.presenter = self
        header.onSortChanged = sortOrderChanged
        configureHeader(header, at: section)
        return header
    }

    @objc private func configureNavigationItem() {
        guard let editDoneButton = navigationItem.rightBarButtonItem else { assertionFailure(); return }
        editDoneButton.isEnabled = {
            if let listNameField = listNameField {
                if !listNameField.isEditing { return true }
                if let newName = listNameField.text, canUpdateListName(to: newName) { return true }
                return false
            }
            return true
        }()
        searchController.searchBar.isEnabled = !isEditing
        if isEditing {
            if listNameField == nil {
                listNameField = listTextField()
                navigationItem.title = nil
            }
        } else {
            if let textField = listNameField {
                textField.removeFromSuperview()
                listNameField = nil
            }
            navigationItem.title = list.name
        }
    }

    private func sortOrderChanged() {
        if searchController.isActive {
            // We don't allow sort order change while the search controller is active; if it does, stop the search.
            assertionFailure()
            searchController.isActive = false
        }
        buildBookSource()
        tableView.reloadData()

        // Put the top row at the "middle", so that the top row is not right up at the top of the table
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: false)
        UserEngagement.logEvent(.changeListSortOrder)
    }

    @objc private func objectContextChanged(_ notification: Notification) {
        guard !ignoreNotifications else { return }
        guard let userInfo = notification.userInfo else { return }

        if (userInfo[NSDeletedObjectsKey] as? NSSet)?.contains(list!) == true {
            // If the list was deleted, pop back. This can't happen through any normal means at the moment.
            navigationController?.popViewController(animated: false)
            return
        }

        // Repopulate the list names cache
        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)

        // If we are not using a controller, reload the table
        if case .orderedSet = listBookSource! {
            tableView.reloadData()
        }
    }

    private func ignoringSaveNotifications(_ block: () -> Void) {
        ignoreNotifications = true
        block()
        ignoreNotifications = false
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performSegue(withIdentifier: "showDetail", sender: indexPath)
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return !tableView.isEditing
    }

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [UITableViewRowAction(style: .destructive, title: "Remove") { _, indexPath in
            let bookToRemove = self.listBookSource.book(at: indexPath)
            self.list.removeBooks(NSSet(object: bookToRemove))
            // Ignore save notifications, so we don't reload the table when using the set: we will remove the row manually
            self.ignoringSaveNotifications {
                self.list.managedObjectContext!.saveAndLogIfErrored()
            }
            if case .orderedSet(let set) = self.listBookSource! {
                let mutableSet = set.mutableCopy() as! NSMutableOrderedSet
                mutableSet.remove(bookToRemove)
                self.listBookSource = .orderedSet(mutableSet)

                if mutableSet.isEmpty {
                    tableView.deleteSections(IndexSet(arrayLiteral: 0), with: .automatic)
                    //TODO //self.dataSource.reloadEmptyStateView()
                } else {
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                }
            }
            UserEngagement.logEvent(.removeBookFromList)
        }]
    }

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
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let detailsViewController = (segue.destination as? UINavigationController)?.topViewController as? BookDetails {
            guard let senderIndex = sender as? IndexPath else { preconditionFailure() }
            let book = listBookSource.book(at: senderIndex)
            detailsViewController.book = book
        }
    }
}

extension ListBookTable: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        reloadHeaders()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}

extension ListBookTable: UISearchResultsUpdating {
    private func getSearchPredicate() -> NSPredicate? {
        guard let searchTerms = searchController.searchBar.text else { return nil }
        if searchTerms.isEmptyOrWhitespace || searchTerms.trimming().count < 2 {
            return nil
        } else {
            return NSPredicate.wordsWithinFields(searchTerms, fieldNames: #keyPath(Book.title), #keyPath(Book.authorSort), "ANY \(#keyPath(Book.subjects)).name")
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let searchPredicate = getSearchPredicate()

        switch listBookSource! {
        case .controller(let controller):
            if let searchPredicate = searchPredicate {
                controller.fetchRequest.predicate = NSPredicate.and([defaultPredicate, searchPredicate])
            } else {
                controller.fetchRequest.predicate = defaultPredicate
            }
            try! controller.performFetch()
        case .orderedSet:
            if let searchPredicate = searchPredicate {
                listBookSource = .orderedSet(list.books.filtered(using: searchPredicate))
            } else {
                listBookSource = .orderedSet(list.books)
            }
        }
        tableView.reloadData()
    }
}

extension ListBookTable: HeaderConfigurable {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int) {
        guard let header = header as? BookTableHeader else { preconditionFailure() }
        let numberOfRows = tableView.numberOfRows(inSection: index)
        if numberOfRows == 0 {
            header.removeFromSuperview()
        } else {
            header.configure(list: list, bookCount: numberOfRows, enableSort: !isEditing && !searchController.isActive)
        }
    }
}

extension ListBookTable: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.text = list.name
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.text = listNameFieldDefaultText
        // If we renamed the list, refresh the empty data set - if present
        if list.books.isEmpty {
            tableView.reloadData()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let newText = textField.text, tryUpdateListName(to: newText) else { return false }
        textField.resignFirstResponder()
        return true
    }
}
