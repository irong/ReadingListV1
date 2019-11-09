import UIKit
import DZNEmptyDataSet
import CoreData
import ReadingList_Foundation
import os.log

class BookTable: UITableViewController { //swiftlint:disable:this type_body_length

    var readStates: [BookReadState]!

    private var resultsController: CompoundFetchedResultsController<Book>!
    private var searchController: UISearchController!
    private var sortManager: SortManager<Book>!
    
    /// An array of tuples of a BookReadState and its associated NSPredicate, in the order the read states should be shown in the table
    private lazy var defaultPredicates = readStates.map {
        (readState: $0, predicate: predicate(for: $0))
    }
    
    /**
     An array of tuples of a BookReadState and its associated NSPredicate, for all BookReadStates. The order is such that the array starts with
     the BookReadStates that are shown in the table, in that order, followed by any other BookReadStates.
    */
    private lazy var allReadStatePredicates: [(readState: BookReadState, predicate: NSPredicate)] = {
        var allReadStates = Array(readStates)
        allReadStates.append(contentsOf: BookReadState.allCases.filter { !readStates.contains($0) })
        return allReadStates.map { ($0, predicate(for: $0)) }
    }()

    private let allReadStatesSearchBarScopeIndex = 1

    override func viewDidLoad() {
        searchController = UISearchController(filterPlaceholderText: "Your Library")
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        // The search bar should have two scope buttons: one which represents the read states shown normally in this VC,
        // the other for "all books".
        searchController.searchBar.scopeButtonTitles = [readStates.map { $0.description }.joined(separator: " & "), "All"]
        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController

        sortManager = SortManager<Book>(tableView) {
            self.resultsController.object(at: $0)
        }

        tableView.keyboardDismissMode = .onDrag
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(BookTableHeader.self)
        tableView.register(BookTableViewCell.self)

        clearsSelectionOnViewWillAppear = false
        navigationItem.title = readStates.last!.description

        // Handle the data fetch, sort and filtering
        buildResultsController(forAllReadStates: false)

        configureNavBarButtons()

        // Set the DZN data set source
        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self

        // Watch for changes
        NotificationCenter.default.addObserver(self, selector: #selector(refetch), name: .PersistentStoreBatchOperationOccurred, object: nil)

        monitorThemeSetting()

        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        // Deselect selected rows, so they don't stay highlighted, but only when in non-split mode
        if let selectedIndexPath = self.tableView.indexPathForSelectedRow, !splitViewController!.detailIsPresented {
            self.tableView.deselectRow(at: selectedIndexPath, animated: animated)
        }
        super.viewDidAppear(animated)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.forceTouchCapability == .available {
            registerForPreviewing(with: self, sourceView: tableView)
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeue(BookTableHeader.self)
        header.presenter = self
        header.onSortChanged = { [unowned self] in
            // All read states are only visible when searching, and when searching, changing of sorts is disabled
            self.buildResultsController(forAllReadStates: false)
            self.tableView.reloadData()
            UserEngagement.logEvent(.changeSortOrder)
        }
        configureHeader(header, at: section)
        return header
    }

    private func predicate(for readState: BookReadState) -> NSPredicate {
        return NSPredicate(format: "%K == %ld", #keyPath(Book.readState), readState.rawValue)
    }

    private func buildResultsController(forAllReadStates: Bool) {
        // The predicates we use as a basis for the fetch requests depends on whether we are displaying all read states or not
        let orderedPredicates: [(readState: BookReadState, predicate: NSPredicate)]
        if forAllReadStates {
            orderedPredicates = allReadStatePredicates
        } else {
            orderedPredicates = defaultPredicates
        }

        let controllers = orderedPredicates.map { readState, predicate -> NSFetchedResultsController<Book> in
            let fetchRequest = NSManagedObject.fetchRequest(Book.self, batch: 25)
            fetchRequest.predicate = predicate
            fetchRequest.sortDescriptors = UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)].sortDescriptors
            return NSFetchedResultsController<Book>(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: #keyPath(Book.readState), cacheName: nil)
        }

        resultsController = CompoundFetchedResultsController(controllers: controllers)
        try! resultsController.performFetch()
        // FUTURE: This is causing causing a retain cycle, but since we don't expect this view controller
        // to get deallocated anyway, it doesn't matter too much.
        resultsController.delegate = self
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        // The search bar should be disabled if editing: searches will clear selections in edit mode,
        // so it's probably better to just prevent searches from occuring.
        searchController.searchBar.isEnabled = !editing

        // If we have stopped editing, reset the navigation title
        if !isEditing {
            navigationItem.title = readStates.last!.description
        }

        configureNavBarButtons()
        reloadHeaders()
    }

    private func configureNavBarButtons() {
        let leftButton, rightButton: UIBarButtonItem
        if isEditing {
            // If we're editing, the right button should become an "edit action" button, but be disabled until any books are selected
            leftButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(toggleEditingAnimated))
            rightButton = UIBarButtonItem(image: #imageLiteral(resourceName: "MoreFilledIcon"), style: .plain, target: self, action: #selector(editActionButtonPressed(_:)))
            rightButton.isEnabled = false
        } else {
            // If we're not editing, the right button should revert back to being an Add button
            leftButton = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(toggleEditingAnimated))
            rightButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addWasPressed(_:)))
        }

        // The edit state may be updated after the emptydataset is shown; the left button should be hidden when empty
        leftButton.setHidden(tableView.isEmptyDataSetVisible)

        navigationItem.leftBarButtonItem = leftButton
        navigationItem.rightBarButtonItem = rightButton
    }

    @objc private func refetch() {
        // FUTURE: This can leave the EmptyDataSet off-screen if a bulk delete has occurred. Can't find a way to prevent this.
        try! self.resultsController.performFetch()
        self.tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return resultsController.sections!.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return resultsController.sections![section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
        let book = resultsController.object(at: indexPath)
        cell.configureFrom(book)
        if #available(iOS 13.0, *) { } else {
            cell.initialise(withTheme: UserDefaults.standard[.theme])
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            guard let selectedRows = tableView.indexPathsForSelectedRows else { return }
            navigationItem.rightBarButtonItem!.isEnabled = true
            navigationItem.title = "\(selectedRows.count) Selected"
        } else {
            guard let selectedCell = tableView.cellForRow(at: indexPath) else { return }
            performSegue(withIdentifier: "showDetail", sender: selectedCell)
        }
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isEditing else { return }
        // If this deselection was deselecting the only selected row, disable the edit action button and reset the title
        if let selectedRows = tableView.indexPathsForSelectedRows, !selectedRows.isEmpty {
            navigationItem.title = "\(selectedRows.count) Selected"
        } else {
            navigationItem.rightBarButtonItem!.isEnabled = false
            navigationItem.title = readStates.last!.description
        }
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return true
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        setEditing(true, animated: true)
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let book = resultsController.object(at: indexPath)
        return UIContextMenuConfiguration(identifier: book.objectID, previewProvider: {
            let bookDetails = UIStoryboard.BookDetails.instantiateViewController(withIdentifier: "BookDetails") as! BookDetails
            bookDetails.book = book
            return bookDetails
        }, actionProvider: { _ in
            var menuItems: [UIMenuElement] = [
                UIAction(title: "Update Notes", image: UIImage(systemName: "text.bubble")) { _ in
                    self.present(EditBookNotes(existingBookID: book.objectID).inThemedNavController(), animated: true)
                },
                UIAction(title: "Manage Lists", image: UIImage(systemName: "tray.2")) { _ in
                    self.present(ManageLists.getAppropriateVcForManagingLists([book]), animated: true)
                },
                UIAction(title: "Edit Book", image: UIImage(systemName: "square.and.pencil")) { _ in
                    self.present(EditBookMetadata(bookToEditID: book.objectID).inThemedNavController(), animated: true)
                },
                UIAction(title: "Manage Log", image: UIImage(systemName: "calendar")) { _ in
                    self.present(EditBookReadState(existingBookID: self.resultsController.object(at: indexPath).objectID).inThemedNavController(), animated: true)
                },
                UIAction(title: "Delete", image: UIImage(systemName: "trash.fill"), attributes: .destructive) { _ in
                    let confirm = self.confirmDeleteAlert(indexPaths: [indexPath])
                    confirm.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
                    self.present(confirm, animated: true)
                }
            ]
            if UserDefaults.standard[UserSettingsCollection.sortSetting(for: book.readState)] == .custom {
                let minSort = Book.minSort(with: book.readState, from: PersistentStoreManager.container.viewContext)
                let maxSort = Book.maxSort(with: book.readState, from: PersistentStoreManager.container.viewContext)
                var moveUpOrDownActions = [UIMenuElement]()
                if let minSort = minSort, book.sort != minSort {
                    moveUpOrDownActions.append(UIAction(title: "Move To Top", image: UIImage(systemName: "arrow.up")) { _ in
                        UserEngagement.logEvent(.moveBookToTop)

                        // Make the data change with the delegate off to prevent automatic table updates
                        self.resultsController.delegate = nil
                        book.sort = minSort - 1
                        book.managedObjectContext!.saveAndLogIfErrored()

                        // Move the row to get a nice animation
                        tableView.moveRow(at: indexPath, to: IndexPath(row: 0, section: indexPath.section))
                        self.resultsController.delegate = self
                    })
                }
                if let maxSort = maxSort, book.sort != maxSort {
                    moveUpOrDownActions.append(UIAction(title: "Move To Bottom", image: UIImage(systemName: "arrow.down")) { _ in
                        UserEngagement.logEvent(.moveBookToBottom)

                        // Make the data change with the delegate off to prevent automatic table updates
                        self.resultsController.delegate = nil
                        book.sort = maxSort + 1
                        book.managedObjectContext!.saveAndLogIfErrored()

                        // Move the row to get a nice animation
                        let rowCount = tableView.numberOfRows(inSection: indexPath.section)
                        tableView.moveRow(at: indexPath, to: IndexPath(row: rowCount - 1, section: indexPath.section))
                        self.resultsController.delegate = self
                    })
                }
                if moveUpOrDownActions.count > 1 {
                    menuItems.insert(UIMenu(title: "Move...", image: UIImage(systemName: "arrow.up.arrow.down"), children: moveUpOrDownActions), at: 0)
                } else if moveUpOrDownActions.count == 1 {
                    menuItems.insert(moveUpOrDownActions[0], at: 0)
                }
            }
            if book.readState == .toRead {
                menuItems.insert(UIAction(title: "Start", image: UIImage(systemName: "play")) { _ in
                    // Schedule the change after a slight delay so that the animation of the row resuming into place does not
                    // interfere with the animation of the row being removed from the table section
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        UserEngagement.logEvent(.transitionReadState)
                        book.setReading(started: Date())
                        book.updateSortIndex()
                        book.managedObjectContext!.saveAndLogIfErrored()
                    }
                }, at: 0)
            } else if book.readState == .reading {
                menuItems.insert(UIAction(title: "Finish", image: UIImage(systemName: "checkmark")) { _ in
                    guard let started = book.startedReading else { return }
                    // Schedule the change after a slight delay so that the animation of the row resuming into place does not
                    // interfere with the animation of the row being removed from the table section
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        UserEngagement.logEvent(.transitionReadState)
                        book.setFinished(started: started, finished: Date())
                        book.updateSortIndex()
                        book.managedObjectContext!.saveAndLogIfErrored()
                    }
                }, at: 0)
            }
            return UIMenu(title: "", children: menuItems)
        })
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let splitViewController = splitViewController else { preconditionFailure("Missing SplitViewController") }
        guard let previewVC = animator.previewViewController else { return }
        if splitViewController.detailIsPresented {
            guard let objectId = configuration.identifier as? NSManagedObjectID else { return }
            let book = PersistentStoreManager.container.viewContext.object(with: objectId) as! Book
            (splitViewController.displayedDetailViewController as? BookDetails)?.book = book
        } else {
            animator.addAnimations {
                self.show(previewVC, sender: self)
            }
        }
    }

    @objc private func editActionButtonPressed(_ sender: UIBarButtonItem) {
        guard let selectedRows = tableView.indexPathsForSelectedRows, !selectedRows.isEmpty else { return }
        let selectedSectionIndices = selectedRows.map { $0.section }.distinct()
        let selectedReadStates = sectionIndexByReadState.filter { selectedSectionIndices.contains($0.value) }.keys

        let optionsAlert = UIAlertController(title: "Edit \(selectedRows.count) book\(selectedRows.count == 1 ? "" : "s")", message: nil, preferredStyle: .actionSheet)
        optionsAlert.addAction(UIAlertAction(title: "Manage Lists", style: .default) { _ in
            let books = selectedRows.map(self.resultsController.object)

            self.present(ManageLists.getAppropriateVcForManagingLists(books) {
                self.setEditing(false, animated: true)
                UserEngagement.logEvent(.bulkAddBookToList)
                UserEngagement.onReviewTrigger()
            }, animated: true)
        })

        if let initialSelectionReadState = selectedReadStates.first, initialSelectionReadState != .finished, selectedReadStates.count == 1 {
            let title = (initialSelectionReadState == .toRead ? "Start" : "Finish") + (selectedRows.count > 1 ? " All" : "")
            optionsAlert.addAction(UIAlertAction(title: title, style: .default) { _ in

                // We need to manage the sort indices manually, since we will be saving the batch operation at once
                let bookSortManager = BookSortIndexManager(context: PersistentStoreManager.container.viewContext,
                                                           readState: initialSelectionReadState == .toRead ? .reading : .finished)
                for book in selectedRows.map(self.resultsController.object) {
                    if initialSelectionReadState == .toRead {
                        book.setReading(started: Date())
                    } else if let started = book.startedReading {
                        book.setFinished(started: started, finished: Date())
                    }
                    book.sort = bookSortManager.getAndIncrementSort()
                }
                PersistentStoreManager.container.viewContext.saveIfChanged()
                self.setEditing(false, animated: true)
                UserEngagement.logEvent(.bulkEditReadState)

                // Only request a review if this was a Start tap: there have been a bunch of reviews
                // on the app store which are for books, not for the app!
                if initialSelectionReadState == .toRead {
                    UserEngagement.onReviewTrigger()
                }
            })
        }

        optionsAlert.addAction(UIAlertAction(title: "Delete\(selectedRows.count > 1 ? " All" : "")", style: .destructive) { _ in
            let confirm = self.confirmDeleteAlert(indexPaths: selectedRows)
            confirm.popoverPresentationController?.barButtonItem = sender
            self.present(confirm, animated: true)
        })
        optionsAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        optionsAlert.popoverPresentationController?.barButtonItem = sender

        self.present(optionsAlert, animated: true, completion: nil)
    }

    private func readStateForSection(_ section: NSFetchedResultsSectionInfo) -> BookReadState {
        guard let sectionNameInt = Int16(section.name), let readState = BookReadState(rawValue: sectionNameInt) else {
            preconditionFailure("Unexpected section name \"\(section.name)\"")
        }
        return readState
    }

    private func readStateForSection(at index: Int) -> BookReadState {
        return readStateForSection(resultsController.sections![index])
    }

    private var sectionIndexByReadState: [BookReadState: Int] {
        guard let sections = resultsController.sections else { preconditionFailure("Cannot get section indexes before fetch") }
        return sections.enumerated().reduce(into: [BookReadState: Int]()) { result, section in
            let readState = readStateForSection(section.element)
            result[readState] = section.offset
        }
    }

    func simulateBookSelection(_ bookID: NSManagedObjectID, allowTableObscuring: Bool = true) {
        let book = PersistentStoreManager.container.viewContext.object(with: bookID) as! Book
        let indexPathOfSelectedBook = self.resultsController.indexPath(forObject: book)

        // If there is a row (there might not be is there is a search filtering the results, and
        // clearing the search creates animations which mess up push segues), then scroll to it.
        if let indexPathOfSelectedBook = indexPathOfSelectedBook {
            tableView.scrollToRow(at: indexPathOfSelectedBook, at: .none, animated: true)
        }

        // allowTableObscuring determines whether the book details page should actually be shown, if showing it will obscure this table
        guard let splitViewController = splitViewController else { preconditionFailure("Missing SplitViewController") }
        guard allowTableObscuring || splitViewController.isSplit else { return }

        if let indexPathOfSelectedBook = indexPathOfSelectedBook {
            tableView.selectRow(at: indexPathOfSelectedBook, animated: true, scrollPosition: .none)
        }

        // If there is a detail view presented, update the book
        if splitViewController.detailIsPresented {
            (splitViewController.displayedDetailViewController as? BookDetails)?.book = book
        } else {
            // Segue to the details view, with the cell corresponding to the book as the sender.
            performSegue(withIdentifier: "showDetail", sender: book)
        }
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        // No clicking on books in edit mode, even if you force-press
        return !tableView.isEditing
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let navController = segue.destination as? UINavigationController,
            let detailsViewController = navController.topViewController as? BookDetails else { return }

        if let cell = sender as? UITableViewCell, let selectedIndex = self.tableView.indexPath(for: cell) {
            detailsViewController.book = self.resultsController.object(at: selectedIndex)
        } else if let book = sender as? Book {
            // When a simulated selection triggers a segue, the sender is the Book
            detailsViewController.book = book
        } else {
            assertionFailure("Unexpected sender type of segue to book details page")
        }
    }

    @IBAction private func addWasPressed(_ sender: UIBarButtonItem) {
        let optionsAlert = UIAlertController(title: "Add New Book", message: nil, preferredStyle: .actionSheet)
        optionsAlert.addAction(UIAlertAction(title: "Scan Barcode", style: .default) { _ in
            self.present(UIStoryboard.ScanBarcode.rootAsFormSheet(), animated: true, completion: nil)
        })
        optionsAlert.addAction(UIAlertAction(title: "Search Online", style: .default) { _ in
            self.present(UIStoryboard.SearchOnline.rootAsFormSheet(), animated: true, completion: nil)
        })
        optionsAlert.addAction(UIAlertAction(title: "Add Manually", style: .default) { _ in
            self.present(EditBookMetadata(bookToCreateReadState: .toRead).inThemedNavController(), animated: true, completion: nil)
        })
        optionsAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        optionsAlert.popoverPresentationController?.barButtonItem = sender

        self.present(optionsAlert, animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let moreImage, deleteImage: UIImage
        if #available(iOS 13.0, *) {
            moreImage = UIImage(systemName: "ellipsis.circle.fill")!
            deleteImage = UIImage(systemName: "trash.fill")!
        } else {
            moreImage = #imageLiteral(resourceName: "More")
            deleteImage = #imageLiteral(resourceName: "Trash")
        }
        return UISwipeActionsConfiguration(performFirstActionWithFullSwipe: false, actions: [
            UIContextualAction(style: .destructive, title: "Delete", image: deleteImage) { _, view, callback in
                let confirm = self.confirmDeleteAlert(indexPaths: [indexPath], callback: callback)
                confirm.popoverPresentationController?.sourceView = view
                self.present(confirm, animated: true, completion: nil)
            },
            UIContextualAction(style: .normal, title: "More", image: moreImage) { _, view, callback in
                let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "Manage Lists", style: .default) { _ in
                    let book = self.resultsController.object(at: indexPath)
                    self.present(ManageLists.getAppropriateVcForManagingLists([book]), animated: true)
                    callback(true)
                })
                alert.addAction(UIAlertAction(title: "Update Notes", style: .default) { _ in
                    let book = self.resultsController.object(at: indexPath)
                    self.present(EditBookNotes(existingBookID: book.objectID).inThemedNavController(), animated: true)
                    callback(true)
                })
                alert.addAction(UIAlertAction(title: "Edit Book", style: .default) { _ in
                    let book = self.resultsController.object(at: indexPath)
                    self.present(EditBookMetadata(bookToEditID: book.objectID).inThemedNavController(), animated: true)
                    callback(true)
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    callback(true)
                })
                alert.popoverPresentationController?.sourceView = view
                self.present(alert, animated: true)
            }
        ])
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {

        let logImage: UIImage
        if #available(iOS 13.0, *) {
            logImage = UIImage(systemName: "calendar")!
        } else {
            logImage = #imageLiteral(resourceName: "Timetable")
        }
        var actions = [UIContextualAction(style: .normal, title: "Log", image: logImage) { _, _, callback in
            self.present(EditBookReadState(existingBookID: self.resultsController.object(at: indexPath).objectID).inThemedNavController(), animated: true)
            callback(true)
        }]

        let readStateOfSection = sectionIndexByReadState.first { $0.value == indexPath.section }!.key
        guard readStateOfSection == .toRead || (readStateOfSection == .reading && resultsController.object(at: indexPath).startedReading! < Date()) else {
            // It is not "invalid" to have a book with a started date in the future; but it is invalid
            // to have a finish date before the start date. Therefore, hide the finish action if
            // this would be the case.
            return UISwipeActionsConfiguration(performFirstActionWithFullSwipe: false, actions: actions)
        }

        let leadingSwipeAction = UIContextualAction(style: .destructive, title: readStateOfSection == .toRead ? "Start" : "Finish") { _, _, callback in
            let book = self.resultsController.object(at: indexPath)
            if readStateOfSection == .toRead {
                book.setReading(started: Date())
                book.updateSortIndex()
            } else if let started = book.startedReading {
                book.setFinished(started: started, finished: Date())
                book.updateSortIndex()
            } else {
                assertionFailure("Unexpected read state")
            }
            book.managedObjectContext!.saveAndLogIfErrored()
            UserEngagement.logEvent(.transitionReadState)
            callback(true)

            // Workaround a strange iOS 13 quirk, where if a swipe leads to a new section appearing, setEditing(false) is not called.
            // This results in the table being unexpectedly in edit mode, and if the search conrtoller is active, it will be stuck:
            // unable to leave edit mode, and unable to select any table cells!
            if #available(iOS 13.0, *) {
                self.setEditing(false, animated: false)
            }
        }
        leadingSwipeAction.backgroundColor = readStateOfSection == .toRead ? UIColor(.buttonBlue) : UIColor(.buttonGreen)
        if #available(iOS 13.0, *) {
            leadingSwipeAction.image = UIImage(systemName: readStateOfSection == .toRead ? "play.fill" : "checkmark")
        } else {
            leadingSwipeAction.image = readStateOfSection == .toRead ? #imageLiteral(resourceName: "Play") : #imageLiteral(resourceName: "Complete")
        }
        actions.insert(leadingSwipeAction, at: 0)

        return UISwipeActionsConfiguration(actions: actions)
    }

    func confirmDeleteAlert(indexPaths: [IndexPath], callback: ((Bool) -> Void)? = nil) -> UIAlertController {
        let confirmDeleteAlert = UIAlertController(title: indexPaths.count == 1 ? "Confirm delete" : "Confirm deletion of \(indexPaths.count) books", message: nil, preferredStyle: .actionSheet)
        confirmDeleteAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            callback?(false)
        })
        confirmDeleteAlert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            indexPaths.map(self.resultsController.object).forEach { $0.delete() }
            PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
            self.setEditing(false, animated: true)
            UserEngagement.logEvent(indexPaths.count > 1 ? .bulkDeleteBook : .deleteBook)
            callback?(true)
        })
        return confirmDeleteAlert
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Disable reorderng when searching, or when the sort order is not custom
        guard !searchController.hasActiveSearchTerms else { return false }
        let readState = readStateForSection(resultsController.sections![indexPath.section])
        guard UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)] == .custom else { return false }

        // We can reorder the books if there are more than one
        return self.tableView(tableView, numberOfRowsInSection: indexPath.section) > 1
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        // Easy case if the sections are the same
        if sourceIndexPath.section == proposedDestinationIndexPath.section {
            return proposedDestinationIndexPath
        }

        // If we are trying to move a cell into the section below this source cell's section, use the largest row value
        if sourceIndexPath.section < proposedDestinationIndexPath.section {
            let sourceSectonRowCount = self.tableView(tableView, numberOfRowsInSection: sourceIndexPath.section)
            return IndexPath(row: sourceSectonRowCount - 1, section: sourceIndexPath.section)
        }

        // Otherwise we must be trying to move a row into the section above the source section: propose a row index of 0
        return IndexPath(row: 0, section: sourceIndexPath.section)
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // We should only have movement within a section
        guard sourceIndexPath.section == destinationIndexPath.section else { return }
        let readState = readStateForSection(at: sourceIndexPath.section)
        guard UserDefaults.standard[UserSettingsCollection.sortSetting(for: readState)] == .custom else { return }

        // Turn off updates while we manipulate the object context
        resultsController.delegate = nil
        sortManager.move(objectAt: sourceIndexPath, to: destinationIndexPath)
        PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
        try! resultsController.performFetch()
        resultsController.delegate = self
    }
}

extension BookTable: UISearchResultsUpdating {
    func predicate(forSearchText searchText: String?) -> NSPredicate {
        if let searchText = searchText, !searchText.isEmptyOrWhitespace && searchText.trimming().count >= 2 {
            return NSPredicate.wordsWithinFields(searchText, fieldNames: #keyPath(Book.title), #keyPath(Book.subtitle), #keyPath(Book.authorSort), "ANY \(#keyPath(Book.subjects)).name")
        }
        return NSPredicate(boolean: true) // If we cannot filter with the search text, we should return all results
    }

    func updateSearchResults(for searchController: UISearchController) {
        let searchTextPredicate = predicate(forSearchText: searchController.searchBar.text)

        var anyChangedPredicates = false
        for (index, controller) in resultsController.controllers.enumerated() {
            // The sequence, in allReadStatePredicates, of read states will match the sequence of the read states
            // each controller is for. There may be less controllers than the size of allReadStatePredicates, though.
            let thisSectionPredicate = NSPredicate.and([allReadStatePredicates[index].predicate, searchTextPredicate])
            if controller.fetchRequest.predicate != thisSectionPredicate {
                controller.fetchRequest.predicate = thisSectionPredicate
                anyChangedPredicates = true
            }
        }
        if anyChangedPredicates {
            try! resultsController.performFetch()
            tableView.reloadData()
        } else {
            reloadHeaders()
        }
    }
}

extension BookTable: UISearchControllerDelegate {
    func didPresentSearchController(_ searchController: UISearchController) {
        if searchController.searchBar.selectedScopeButtonIndex == allReadStatesSearchBarScopeIndex {
            buildResultsController(forAllReadStates: true)
            updateSearchResults(for: searchController)
        }
    }
}

extension BookTable: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        buildResultsController(forAllReadStates: selectedScope == allReadStatesSearchBarScopeIndex)
        updateSearchResults(for: searchController)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        if searchBar.selectedScopeButtonIndex == allReadStatesSearchBarScopeIndex {
            buildResultsController(forAllReadStates: false)
        }
    }
}

extension BookTable: HeaderConfigurable {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int) {
        guard let header = header as? BookTableHeader else { preconditionFailure() }
        header.configure(readState: readStateForSection(at: index), bookCount: resultsController.sections![index].numberOfObjects,
                         enableSort: !isEditing && !searchController.isActive)
    }
}

extension BookTable: NSFetchedResultsControllerDelegate {
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

extension BookTable: UIViewControllerPreviewingDelegate {
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard !tableView.isEditing else { return nil }
        guard let indexPath = tableView.indexPathForRow(at: location), let cell = tableView.cellForRow(at: indexPath) else {
            return nil
        }

        previewingContext.sourceRect = cell.frame
        let bookDetails = UIStoryboard.BookDetails.instantiateViewController(withIdentifier: "BookDetails") as! BookDetails
        bookDetails.book = resultsController.object(at: indexPath)
        return bookDetails
    }

    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        show(viewControllerToCommit, sender: self)
    }
}

extension BookTable: DZNEmptyDataSetSource {
    func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        if searchController.hasActiveSearchTerms {
            return title("🔍 No Results")
        } else if readStates.contains(.reading) {
            return title("📚 To Read")
        } else {
            return title("🎉 Finished")
        }
    }

    func verticalOffset(forEmptyDataSet scrollView: UIScrollView!) -> CGFloat {
        return -30
    }

    func description(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        if searchController.hasActiveSearchTerms {
            return noResultsDescription(for: "book")
        }

        let attributedDescription: NSMutableAttributedString
        if readStates.contains(.reading) {
            attributedDescription = NSMutableAttributedString("Books you add to your ", font: descriptionFont)
                .appending("To Read", font: boldDescriptionFont)
                .appending(" list, or mark as currently ", font: descriptionFont)
                .appending("Reading", font: boldDescriptionFont)
                .appending(" will show up here.", font: descriptionFont)
        } else {
            attributedDescription = NSMutableAttributedString("Books you mark as ", font: descriptionFont)
                .appending("Finished", font: boldDescriptionFont)
                .appending(" will show up here.", font: descriptionFont)
        }
        return applyDescriptionAttributes(
            attributedDescription.appending("\n\nAdd a book by tapping the ", font: descriptionFont)
                .appending("+", font: boldDescriptionFont)
                .appending(" button above.", font: descriptionFont)
        )
    }
}

extension BookTable: DZNEmptyDataSetDelegate {
    func emptyDataSetWillAppear(_ scrollView: UIScrollView!) {
        navigationItem.leftBarButtonItem!.setHidden(true)
        navigationItem.largeTitleDisplayMode = .never
    }

    func emptyDataSetWillDisappear(_ scrollView: UIScrollView!) {
        navigationItem.leftBarButtonItem!.setHidden(false)
        navigationItem.largeTitleDisplayMode = .automatic
    }
}

extension Book: Sortable {
    var sortIndex: Int32 {
        get { return sort }
        set(newValue) { sort = newValue }
    }
}
