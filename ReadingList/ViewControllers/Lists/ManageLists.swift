import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

class ManageLists: UITableViewController {
    var books: [Book]!
    var onComplete: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        if books.isEmpty { preconditionFailure() }
        if books.count == 1 {
            NotificationCenter.default.addObserver(self, selector: #selector(saveOccurred(_:)), name: .NSManagedObjectContextDidSave, object: PersistentStoreManager.container.viewContext)
        }
    }

    @objc private func saveOccurred(_ notification: Notification) {
        // In case the book's list membership changes, reload the table so that the second section is shown or hidden accordingly
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        if books.count > 1 || books[0].lists.isEmpty { return 1 }
        return 2
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 && indexPath.row == 0 {
            present(ManageLists.newListAlertController(books) { [unowned self] _ in
                self.navigationController?.dismiss(animated: true, completion: self.onComplete)
            }, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        if let addToExistingLists = segue.destination as? AddToExistingLists {
            addToExistingLists.books = books
            addToExistingLists.onComplete = onComplete
        } else if let removeFromExistingLists = segue.destination as? RemoveFromExistingLists {
            guard books.count == 1 else { preconditionFailure() }
            guard !books[0].lists.isEmpty else { assertionFailure(); return }
            removeFromExistingLists.book = books[0]
        }
    }

    @IBAction private func doneTapped(_ sender: Any) {
        navigationController?.dismiss(animated: true)
    }

    static func newListAlertController(_ books: [Book], onComplete: ((List) -> Void)? = nil) -> UIAlertController {
        let existingListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)

        func textValidator(listName: String?) -> Bool {
            guard let listName = listName, !listName.isEmptyOrWhitespace else { return false }
            return !existingListNames.contains(listName)
        }

        return TextBoxAlert(title: "Add New List", message: "Enter a name for your list", placeholder: "Enter list name",
                            keyboardAppearance: UserDefaults.standard[.theme].keyboardAppearance, textValidator: textValidator) {
            let createdList = List(context: PersistentStoreManager.container.viewContext, name: $0!)
            createdList.books = NSOrderedSet(array: books)
            PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
            onComplete?(createdList)
        }
    }

    /*
     Returns the appropriate View Controller for adding a book (or books) to a list. If there are no lists, this
     will be a UIAlertController; otherwise, a UINavigationController. onComplete only called if some action was
     taken (rather than just cancelling the dialog, for example).
     */
    static func getAppropriateVcForManagingLists(_ booksToAdd: [Book], onComplete: (() -> Void)? = nil) -> UIViewController {
        let listCount = NSManagedObject.fetchRequest(List.self, limit: 1)
        if try! PersistentStoreManager.container.viewContext.count(for: listCount) > 0 {
            let rootAddToList = UIStoryboard.ManageLists.instantiateRoot(withStyle: .formSheet) as! UINavigationController
            let manageLists = rootAddToList.viewControllers[0] as! ManageLists
            manageLists.books = booksToAdd
            manageLists.onComplete = onComplete
            return rootAddToList
        } else {
            return ManageLists.newListAlertController(booksToAdd) { _ in
                onComplete?()
            }
        }
    }
}
