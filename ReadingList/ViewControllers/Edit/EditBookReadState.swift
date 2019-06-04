import Foundation
import Eureka
import UIKit
import CoreData

class EditBookReadState: FormViewController {

    private var editContext: NSManagedObjectContext!
    private var book: Book!
    private var newBook = false

    private let currentPageKey = "currentPage"
    private let readStateKey = "readState"
    private let startedReadingKey = "startedReading"
    private let finishedReadingKey = "finishedReading"

    convenience init(existingBookID: NSManagedObjectID) {
        self.init()
        editContext = PersistentStoreManager.container.viewContext.childContext()
        book = (editContext.object(with: existingBookID) as! Book)
    }

    convenience init(newUnsavedBook: Book, scratchpadContext: NSManagedObjectContext) {
        self.init()
        newBook = true
        book = newUnsavedBook
        editContext = scratchpadContext
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationItem()

        // Watch the book object for changes and validate the form
        NotificationCenter.default.addObserver(self, selector: #selector(validateBook), name: .NSManagedObjectContextObjectsDidChange, object: editContext)

        let now = Date()

        form +++ Section(header: "Reading Log", footer: "")
            <<< SegmentedRow<BookReadState>(readStateKey) {
                $0.options = [.toRead, .reading, .finished]
                $0.value = book.readState
                $0.onChange { [unowned self] _ in
                    self.updateBookFromForm()
                }
            }
            <<< DateRow(startedReadingKey) {
                $0.title = "Started"
                $0.value = book.startedReading ?? now
                $0.onChange { [unowned self] _ in
                    self.updateBookFromForm()
                }
                $0.hidden = Condition.function([readStateKey]) { [unowned self] form in
                    (form.rowBy(tag: self.readStateKey) as! SegmentedRow<BookReadState>).value == .toRead
                }
            }
            <<< DateRow(finishedReadingKey) {
                $0.title = "Finished"
                $0.value = book.finishedReading ?? now
                $0.onChange { [unowned self] _ in
                    self.updateBookFromForm()
                }
                $0.hidden = Condition.function([readStateKey]) { [unowned self] form in
                    (form.rowBy(tag: self.readStateKey) as! SegmentedRow<BookReadState>).value != .finished
                }
            }
            <<< Int32Row(currentPageKey) {
                $0.title = "Current Page"
                $0.value = book.currentPage
                $0.onChange { [unowned self] cell in
                    self.book.currentPage = cell.value
                }
                $0.hidden = Condition.function([readStateKey]) { [unowned self] form in
                    (form.rowBy(tag: self.readStateKey) as! SegmentedRow<BookReadState>).value != .reading
                }
            }

        monitorThemeSetting()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // If we are editing a book (not adding one), pre-select the current page field
        if self.book.readState == .reading && self.book.changedValues().isEmpty {
            let currentPageRow = self.form.rowBy(tag: currentPageKey) as! Int32Row
            currentPageRow.cell.textField.becomeFirstResponder()
        }
    }

    private func updateBookFromForm() {
        let readState = (form.rowBy(tag: readStateKey) as! SegmentedRow<BookReadState>).value ?? .toRead
        if readState == .toRead {
            book.setToRead()
        } else if readState == .reading {
            book.setReading(started: (form.rowBy(tag: startedReadingKey) as! DateRow).value ?? Date())
            book.currentPage = (form.rowBy(tag: currentPageKey) as! Int32Row).value
        } else {
            book.setFinished(started: (form.rowBy(tag: startedReadingKey) as! DateRow).value ?? Date(),
                             finished: (form.rowBy(tag: finishedReadingKey) as! DateRow).value ?? Date())
        }
    }

    func configureNavigationItem() {
        if navigationItem.leftBarButtonItem == nil && navigationController!.viewControllers.first == self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))
        }
        navigationItem.title = book.title
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePressed))
    }

    @objc func validateBook() {
        navigationItem.rightBarButtonItem!.isEnabled = book.isValidForUpdate()
    }

    @objc func cancelPressed() {
        // FUTURE: Duplicates code in EditBookMetadata. Consolidate.
        updateBookFromForm()
        guard book.changedValues().isEmpty else {
            // Confirm exit dialog
            let confirmExit = UIAlertController(title: "Unsaved changes", message: "Are you sure you want to discard your unsaved changes?", preferredStyle: .actionSheet)
            confirmExit.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
                self.dismiss(animated: true)
            })
            confirmExit.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            present(confirmExit, animated: true, completion: nil)
            return
        }

        dismiss(animated: true, completion: nil)
    }

    @objc func donePressed() {
        guard book.isValidForUpdate() else { return }
        view.endEditing(true)

        if newBook || book.changedValues().keys.contains(#keyPath(Book.readState)) {
            book.updateSortIndex()
        }
        // If we have been adding a new manual book with a language, remember this language.
        // Note: this has a limitation that it does not detect manually selected languages from a book added from an
        // online search (after tapping the detail button), since we are unable to determine whether the language
        // currently set in the book is equal to what was present in the search result. This is acceptable for now.
        if let language = book.language, book.manualBookId != nil && newBook {
            UserDefaults.standard[.lastSelectedLanguage] = language
        }
        editContext.saveIfChanged()

        // FUTURE: Figure out a better way to solve this problem.
        // If the previous view controller was the SearchOnline VC, then we need to deactivate its search controller
        // so that it doesn't end up being leaked. We can't do that on viewWillDissappear, since that would clear the
        // search bar, which is annoying if the user navigates back to that view.
        if let searchOnline = navigationController!.viewControllers.first as? SearchOnline {
            searchOnline.searchController.isActive = false
        }

        presentingViewController?.dismiss(animated: true) {
            if self.newBook {
                guard let tabBarController = AppDelegate.shared.tabBarController else {
                    assertionFailure()
                    return
                }
                tabBarController.simulateBookSelection(self.book, allowTableObscuring: false)
            }
            UserEngagement.onReviewTrigger()
        }
    }
}
