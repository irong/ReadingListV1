import UIKit
import DZNEmptyDataSet
import CoreData
import ReadingList_Foundation
import os.log

class BookTable: UITableViewController { //swiftlint:disable:this type_body_length

    var resultsController: CompoundFetchedResultsController<Book>!
    var readStates: [BookReadState]!
    var searchController: UISearchController!
    private lazy var orderedDefaultPredicates = readStates.map {
        (readState: $0, predicate: NSPredicate(format: "%K == %ld", #keyPath(Book.readState), $0.rawValue))
    }

    override func viewDidLoad() {
        searchController = UISearchController(filterPlaceholderText: "Your Library")
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController

        tableView.keyboardDismissMode = .onDrag
        tableView.register(UINib(BookTableViewCell.self), forCellReuseIdentifier: String(describing: BookTableViewCell.self))

        clearsSelectionOnViewWillAppear = false
        navigationItem.title = readStates.last!.description

        // Handle the data fetch, sort and filtering
        buildResultsController()

        configureNavBarButtons()

        // Set the DZN data set source
        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self

        // Watch for changes
        NotificationCenter.default.addObserver(self, selector: #selector(bookSortChanged), name: .BookSortOrderChanged, object: nil)
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

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return titleForHeader(inSection: section)
    }

    func titleForHeader(inSection section: Int) -> String {
        // Turn the section name into a BookReadState and use its description property
        let sectionAsInt = Int(resultsController.sections![section].name)!
        let rowCount = resultsController.sections![section].numberOfObjects
        return "\(BookReadState(rawValue: Int16(sectionAsInt))!.description.uppercased()) (\(rowCount))"
    }

    func buildResultsController() {
        let controllers = orderedDefaultPredicates.map { readState, predicate -> NSFetchedResultsController<Book> in
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
        searchController.searchBar.isActive = !editing

        // If we have stopped editing, reset the navigation title
        if !isEditing {
            navigationItem.title = readStates.last!.description
        }

        configureNavBarButtons()
    }

    func configureNavBarButtons() {
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

    @objc func bookSortChanged() {
        DispatchQueue.main.async { // I should've commented why this is async; I don't remember why
            self.buildResultsController()
            self.tableView.reloadData()
        }
    }

    @objc func refetch() {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookTableViewCell", for: indexPath) as! BookTableViewCell
        let book = resultsController.object(at: indexPath)
        cell.configureFrom(book)
        cell.initialise(withTheme: UserDefaults.standard[.theme])
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
        if let selectedRows = tableView.indexPathForSelectedRow, !selectedRows.isEmpty {
            navigationItem.title = "\(selectedRows.count) Selected"
        } else {
            navigationItem.rightBarButtonItem!.isEnabled = false
            navigationItem.title = readStates.last!.description
        }
    }

    @objc func editActionButtonPressed(_ sender: UIBarButtonItem) {
        guard let selectedRows = tableView.indexPathsForSelectedRows, !selectedRows.isEmpty else { return }
        let selectedSectionIndices = selectedRows.map { $0.section }.distinct()
        let selectedReadStates = sectionIndexByReadState.filter { selectedSectionIndices.contains($0.value) }.keys

        let optionsAlert = UIAlertController(title: "Edit \(selectedRows.count) book\(selectedRows.count == 1 ? "" : "s")", message: nil, preferredStyle: .actionSheet)
        optionsAlert.addAction(UIAlertAction(title: "Add to List", style: .default) { _ in
            let books = selectedRows.map(self.resultsController.object)

            self.present(AddToList.getAppropriateVcForAddingBooksToList(books) { _ in
                self.setEditing(false, animated: true)
                UserEngagement.logEvent(.bulkAddBookToList)
                UserEngagement.onReviewTrigger()
            }, animated: true)
        })

        if let initialSelectionReadState = selectedReadStates.first, initialSelectionReadState != .finished, selectedReadStates.count == 1 {
            let title = (initialSelectionReadState == .toRead ? "Start" : "Finish") + (selectedRows.count > 1 ? " All" : "")
            optionsAlert.addAction(UIAlertAction(title: title, style: .default) { _ in
                for book in selectedRows.map(self.resultsController.object) {
                    if initialSelectionReadState == .toRead {
                        book.setReading(started: Date())
                    } else if let started = book.startedReading {
                        book.setFinished(started: started, finished: Date())
                    }
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

    var sectionIndexByReadState: [BookReadState: Int] {
        guard let sections = resultsController.sections else { preconditionFailure("Cannot get section indexes before fetch") }
        return sections.enumerated().reduce(into: [BookReadState: Int]()) { result, section in
            guard let sectionNameInt = Int16(section.element.name), let readState = BookReadState(rawValue: sectionNameInt) else {
                preconditionFailure("Unexpected section name \"\(section.element.name)\"")
            }
            result[readState] = section.offset
        }
    }

    func simulateBookSelection(_ bookID: NSManagedObjectID, allowTableObscuring: Bool = true) {
        let book = PersistentStoreManager.container.viewContext.object(with: bookID) as! Book
        let indexPathOfSelectedBook = self.resultsController.indexPath(forObject: book)

        // If there is a row (there might not be is there is a search filtering the results,
        // and clearing the search creates animations which mess up push segues), then
        // scroll to it.
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

        func storyboardAction(title: String, storyboard: UIStoryboard) -> UIAlertAction {
            return UIAlertAction(title: title, style: .default) { _ in
                self.present(storyboard.rootAsFormSheet(), animated: true, completion: nil)
            }
        }

        let optionsAlert = UIAlertController(title: "Add New Book", message: nil, preferredStyle: .actionSheet)
        optionsAlert.addAction(storyboardAction(title: "Scan Barcode", storyboard: .ScanBarcode))
        optionsAlert.addAction(storyboardAction(title: "Search Online", storyboard: .SearchOnline))
        optionsAlert.addAction(UIAlertAction(title: "Add Manually", style: .default) { _ in
            self.present(EditBookMetadata(bookToCreateReadState: .toRead).inThemedNavController(), animated: true, completion: nil)
        })
        optionsAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        optionsAlert.popoverPresentationController?.barButtonItem = sender

        self.present(optionsAlert, animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, callback in
            let confirm = self.confirmDeleteAlert(indexPaths: [indexPath], callback: callback)
            confirm.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
            self.present(confirm, animated: true, completion: nil)
        }
        deleteAction.image = #imageLiteral(resourceName: "Trash")
        let editAction = UIContextualAction(style: .normal, title: "Edit") { _, _, callback in
            self.present(EditBookMetadata(bookToEditID: self.resultsController.object(at: indexPath).objectID).inThemedNavController(), animated: true)
            callback(true)
        }
        editAction.image = #imageLiteral(resourceName: "Literature")
        return UISwipeActionsConfiguration(performFirstActionWithFullSwipe: false, actions: [deleteAction, editAction])
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {

        var actions = [UIContextualAction(style: .normal, title: "Log", image: #imageLiteral(resourceName: "Timetable")) { _, _, callback in
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

        let leadingSwipeAction = UIContextualAction(style: .normal, title: readStateOfSection == .toRead ? "Start" : "Finish") { _, _, callback in
            let book = self.resultsController.object(at: indexPath)
            if readStateOfSection == .toRead {
                book.setReading(started: Date())
            } else if let started = book.startedReading {
                book.setFinished(started: started, finished: Date())
            }
            book.managedObjectContext!.saveAndLogIfErrored()
            UserEngagement.logEvent(.transitionReadState)
            callback(true)
        }
        leadingSwipeAction.backgroundColor = readStateOfSection == .toRead ? .buttonBlue : .flatGreen
        leadingSwipeAction.image = readStateOfSection == .toRead ? #imageLiteral(resourceName: "Play") : #imageLiteral(resourceName: "Complete")
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
        guard let toReadSectionIndex = sectionIndexByReadState[.toRead] else { return false }
        guard UserDefaults.standard[.toReadSort] == .custom else { return false }

        // We can reorder the "ToRead" books if there are more than one
        return indexPath.section == toReadSectionIndex && self.tableView(tableView, numberOfRowsInSection: toReadSectionIndex) > 1
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        if sourceIndexPath.section == proposedDestinationIndexPath.section {
            return proposedDestinationIndexPath
        } else {
            // FUTURE: To work best in the general case, this should see whether the proposed section is lower or higher
            // than the source section, and use that to set the returned IndexPath's row to either 0 or the maximum (respectively)
            return IndexPath(row: 0, section: sourceIndexPath.section)
        }
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // We should only have movement in the ToRead secion. We also ignore moves which have no effect
        guard let toReadSectionIndex = sectionIndexByReadState[.toRead] else { return }
        guard sourceIndexPath.section == toReadSectionIndex && destinationIndexPath.section == toReadSectionIndex else { return }
        guard sourceIndexPath.row != destinationIndexPath.row else { return }

        // Get the range of objects that the move affects
        let topRowIndex = sourceIndexPath.row < destinationIndexPath.row ? sourceIndexPath : destinationIndexPath
        let bottomRowIndex = sourceIndexPath.row < destinationIndexPath.row ? destinationIndexPath : sourceIndexPath
        let downwardMovement = sourceIndexPath.row < destinationIndexPath.row
        var booksInMovementRange = (topRowIndex.row...bottomRowIndex.row).map {
            resultsController.object(at: IndexPath(row: $0, section: toReadSectionIndex))
        }

        // Move the objects array to reflect the desired order
        if downwardMovement {
            let first = booksInMovementRange.removeFirst()
            booksInMovementRange.append(first)
        } else {
            let last = booksInMovementRange.removeLast()
            booksInMovementRange.insert(last, at: 0)
        }

        // Turn off updates while we manipulate the object context
        resultsController.delegate = nil

        // Get the desired sort index for the top row in the movement range. This will be the basis
        // of our new sort values.
        let topRowSort = getDesiredSort(for: topRowIndex)

        // Update the sort indices for all books in the range, increasing the sort by 1 for each cell.
        var sort = topRowSort
        for book in booksInMovementRange {
            book.sort = sort
            sort += 1
        }

        // The following operation does not strictly follow from this reorder operation: we want to ensure that
        // we don't have overlapping sort indices. This shoudn't happen in normal usage of the app - but distinct
        // values are not enforced in the data model. Overlap might occur due to difficult-to-avoid timing issues
        // in iCloud sync. We take advantage of this time to clean up any mess that may be present.
        cleanupClashingSortIndices(from: bottomRowIndex.next(), withSort: sort)

        PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
        try! resultsController.performFetch()

        // Enable updates again
        resultsController.delegate = self
    }

    private func getDesiredSort(for indexPath: IndexPath) -> Int32 {
        // The desired sort index should be the sort of the book immediately above the specified cell,
        // plus 1, or - if the cell is at the top - the value of the current minimum sort.
        guard indexPath.row != 0 else {
            return Book.minSort(fromContext: PersistentStoreManager.container.viewContext) ?? 0
        }
        let indexPathAboveCell = indexPath.previous()
        guard let sortIndexAboveCell = resultsController.object(at: indexPathAboveCell).sort else {
            preconditionFailure("Book at index (\(indexPathAboveCell.section), \(indexPathAboveCell.row)) has nil sort")
        }
        return sortIndexAboveCell + 1
    }

    private func cleanupClashingSortIndices(from topIndexPath: IndexPath, withSort topSort: Int32) {
        var cleanupIndex = topIndexPath
        while cleanupIndex.row < tableView.numberOfRows(inSection: cleanupIndex.section) {
            let cleanupBook = resultsController.object(at: cleanupIndex)
            let cleanupSort = Int32(cleanupIndex.row - topIndexPath.row) + topSort

            // No need to proceed if the sort index is large enough
            if let currentSort = cleanupBook.sort, currentSort >= cleanupSort { break }

            os_log("Adjusting sort index of book at index %d from %{public}s to %d.", type: .debug, cleanupIndex.row, String(describing: cleanupBook.sort), cleanupSort)

            cleanupBook.sort = cleanupSort
            cleanupIndex = cleanupIndex.next()
        }
    }
}

extension BookTable: UISearchResultsUpdating {
    func predicate(forSearchText searchText: String?) -> NSPredicate {
        if let searchText = searchText, !searchText.isEmptyOrWhitespace && searchText.trimming().count >= 2 {
            return NSPredicate.wordsWithinFields(searchText, fieldNames: #keyPath(Book.title), #keyPath(Book.authorSort), "ANY \(#keyPath(Book.subjects)).name")
        }
        return NSPredicate(boolean: true) // If we cannot filter with the search text, we should return all results
    }

    func updateSearchResults(for searchController: UISearchController) {
        let searchTextPredicate = self.predicate(forSearchText: searchController.searchBar.text)

        var anyChangedPredicates = false
        for (index, controller) in resultsController.controllers.enumerated() {
            let thisSectionPredicate = NSPredicate.and([orderedDefaultPredicates[index].predicate, searchTextPredicate])
            if controller.fetchRequest.predicate != thisSectionPredicate {
                controller.fetchRequest.predicate = thisSectionPredicate
                anyChangedPredicates = true
            }
        }
        if anyChangedPredicates {
            try! resultsController.performFetch()
            tableView.reloadData()
        }
    }
}

extension BookTable: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()

        // Reload the footer text whenever content changes
        for section in 0..<resultsController.sections!.count {
            let title = titleForHeader(inSection: section)
            guard let headerView = tableView.headerView(forSection: section) else { continue }
            headerView.textLabel?.text = title
            headerView.sizeToFit()
        }
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
            return StandardEmptyDataset.title(withText: "🔍 No Results")
        } else if readStates.contains(.reading) {
            return StandardEmptyDataset.title(withText: "📚 To Read")
        } else {
            return StandardEmptyDataset.title(withText: "🎉 Finished")
        }
    }

    func verticalOffset(forEmptyDataSet scrollView: UIScrollView!) -> CGFloat {
        return -30
    }

    func description(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        if searchController.hasActiveSearchTerms {
            return StandardEmptyDataset.description(withMarkdownText: """
                Try changing your search, or add a new book by tapping the **+** button above.
                """)
        }
        if readStates.contains(.reading) {
            return StandardEmptyDataset.description(withMarkdownText: """
                Books you add to your **To Read** list, or mark as currently **Reading** will show up here.

                Add a book by tapping the **+** button above.
                """)
        } else {
            return StandardEmptyDataset.description(withMarkdownText: """
                Books you mark as **Finished** will show up here.

                Add a book by tapping the **+** button above.
                """)
        }
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
