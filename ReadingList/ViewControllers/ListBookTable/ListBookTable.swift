import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

final class ListBookTable: UITableViewController {

    var list: List!
    private var cachedListNames: [String]!
    private var ignoreNotifications = false

    private var searchController: UISearchController!
    private var dataSource: ListBookDataSource!
    private var emptyStateManager: ListBookTableEmptyDataSetManager!

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

        tableView.register(BookTableViewCell.self)
        tableView.register(BookTableHeader.self)

        // Cache the list names so we know which names are disallowed when editing this list's name
        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
        navigationItem.title = list.name
        navigationItem.rightBarButtonItem = editButtonItem

        searchController = UISearchController(filterPlaceholderText: "Filter List")
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        navigationItem.searchController = searchController

        if #available(iOS 13.0, *) {
            dataSource = ListBookDiffableDataSource(tableView, list: list, dataProvider: buildDiffableDataProvider(), searchController: searchController, onContentChanged: reloadHeaders)
        } else {
            dataSource = ListBookLegacyDataSource(tableView, list: list, dataProvider: buildLegacyDataProvider(), searchController: searchController, onContentChanged: reloadHeaders)
        }

        // Configure the empty state manager to detect when the table becomes empty
        emptyStateManager = ListBookTableEmptyDataSetManager(tableView: tableView, navigationBar: navigationController?.navigationBar, navigationItem: navigationItem, searchController: searchController, list: list)
        dataSource.emptyDetectionDelegate = emptyStateManager
        dataSource.updateData(animate: false)

        NotificationCenter.default.addObserver(self, selector: #selector(objectContextChanged(_:)),
                                               name: .NSManagedObjectContextDidSave,
                                               object: PersistentStoreManager.container.viewContext)
        monitorThemeSetting()
    }

    private func rebuildDataProvider() {
        if #available(iOS 13.0, *), let diffableDataSource = dataSource as? ListBookDiffableDataSource {
            diffableDataSource.diffableDataProvider = buildDiffableDataProvider()
        } else if let legacyDataSource = dataSource as? ListBookLegacyDataSource {
            legacyDataSource.legacyDataProvider = buildLegacyDataProvider()
        } else {
            preconditionFailure()
        }
    }

    @available(iOS 13.0, *)
    private func buildDiffableDataProvider() -> DiffableListBookDataProvider {
        if list.order == .listCustom {
            // We cannot use a fetched results controller when ordering by the underlying ordered predicate order.
            // Instead, we just use the ordered set as our source.
            return DiffableListBookSetDataProvider(list)
        } else {
            return DiffableListBookControllerDataProvider(buildResultsController())
        }
    }

    @available(iOS, obsoleted: 13.0)
    private func buildLegacyDataProvider() -> LegacyListBookDataProvider {
        if list.order == .listCustom {
            return LegacyListBookSetDataProvider(list)
        } else {
            return LegacyListBookControllerDataProvider(buildResultsController())
        }
    }

    private func buildResultsController() -> NSFetchedResultsController<Book> {
        let fetchRequest = NSManagedObject.fetchRequest(Book.self, batch: 50)
        fetchRequest.predicate = defaultPredicate
        fetchRequest.sortDescriptors = list.order.sortDescriptors
        let controller = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                    managedObjectContext: PersistentStoreManager.container.viewContext,
                                                    sectionNameKeyPath: nil, cacheName: nil)
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
        rebuildDataProvider()
        dataSource.updateData(animate: true)

        // Put the top row at the "middle", so that the top row is not right up at the top of the table
        //is this needed? tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: false)
        UserEngagement.logEvent(.changeListSortOrder)
    }

    @objc private func objectContextChanged(_ notification: Notification) {
        guard !ignoreNotifications else { return }
        guard let userInfo = notification.userInfo else { return }

        if let deletedObjects = userInfo[NSDeletedObjectsKey] as? NSSet, deletedObjects.contains(list!) {
            // If the list was deleted, pop back. This can't happen through any normal means at the moment.
            navigationController?.popViewController(animated: false)
            return
        }

        // Repopulate the list names cache
        cachedListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
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
            let bookToRemove = self.dataSource.getBook(at: indexPath)

            // This does the actual removal
            self.list.removeBooks(NSSet(object: bookToRemove))

            // We don't have "nice" automatic handling of book removal from a list when using the legacy set based data provider.
            // We can detect that case, though, and handle the row removal ourselves.
            if let legacyDataSource = self.dataSource as? ListBookLegacyDataSource, let dataProvider = legacyDataSource.dataProvider as? LegacyListBookSetDataProvider {
                // Remove the dataSource reference from the dataProvider, so it cannot request a reload of the table
                dataProvider.dataSource = nil
                self.list.managedObjectContext!.saveAndLogIfErrored()

                // Perform the table update
                if self.list.books.isEmpty {
                    tableView.deleteSections(IndexSet(arrayLiteral: 0), with: .automatic)
                    self.emptyStateManager.reloadEmptyStateView()
                } else {
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                }

                // Reactivate change detection
                dataProvider.dataSource = legacyDataSource

                // Reload the headers to refresh the book count
                self.reloadHeaders()
            } else {
                self.list.managedObjectContext!.saveAndLogIfErrored()
            }

            UserEngagement.logEvent(.removeBookFromList)
        }]
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let detailsViewController = (segue.destination as? UINavigationController)?.topViewController as? BookDetails {
            guard let senderIndex = sender as? IndexPath else { preconditionFailure() }
            let book = dataSource.getBook(at: senderIndex)
            detailsViewController.book = book
        }
    }
}

extension ListBookTable: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        // If we caused all data to be deleted while searching, the empty state view might now need to be a "no books" view
        // rather than a "no results" view.
        emptyStateManager.reloadEmptyStateView()
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

        if let controllerDataProvider = dataSource.dataProvider as? ListBookControllerDataProvider {
            if let searchPredicate = searchPredicate {
                controllerDataProvider.controller.fetchRequest.predicate = NSPredicate.and([defaultPredicate, searchPredicate])
            } else {
                controllerDataProvider.controller.fetchRequest.predicate = defaultPredicate
            }
            try! controllerDataProvider.controller.performFetch()
        } else if var setDataProvider = dataSource.dataProvider as? ListBookSetDataProvider {
            if let searchPredicate = searchPredicate {
                setDataProvider.filterPredicate = searchPredicate
            } else {
                setDataProvider.filterPredicate = NSPredicate(boolean: true)
            }
        } else {
            preconditionFailure("Unexpected data provider type: \(dataSource.dataProvider)")
        }

        dataSource.updateData(animate: true)
    }
}

extension ListBookTable: HeaderConfigurable {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int) {
        guard let header = header as? BookTableHeader else { preconditionFailure() }
        let numberOfRows: Int
        if let controllerDataProvider = dataSource.dataProvider as? ListBookControllerDataProvider {
            numberOfRows = controllerDataProvider.controller.sections![0].numberOfObjects
        } else if let setDataProvider = dataSource.dataProvider as? ListBookSetDataProvider {
            numberOfRows = setDataProvider.books.count
        } else {
            preconditionFailure("Unexpected data provider type \(dataSource.dataProvider)")
        }

        if numberOfRows == 0 {
            assertionFailure("Should not be configuring a header when there are no books.")
        }
        header.configure(list: list, bookCount: numberOfRows, enableSort: !isEditing && !searchController.isActive)
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
