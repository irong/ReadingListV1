import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

class AddToList: UITableViewController {

    // Since this view is only brought up as a modal dispay, it is probably not necessary to implement
    // change detection via a NSFetchedResultsControllerDelegate.
    var resultsController: NSFetchedResultsController<List>!

    // Holds the books which are to be added to a list. The set form is just for convenience.
    var books: [Book]! {
        didSet {
            booksSet = NSSet(array: books)
        }
    }
    var booksSet: NSSet!

    private let addNewListSectionIndex = 0

    // When the add-to-list operation is complete, this callback will be called
    var onCompletion: ((List) -> Void)?

    /*
     Returns the appropriate View Controller for adding a book (or books) to a list.
     If there are no lists, this will be a UIAlertController; if there are lists, this will be a UINavigationController.
     The completion action will run at the end of a list addition if a UIAlertController was returned.
    */
    static func getAppropriateVcForAddingBooksToList(_ booksToAdd: [Book], completion: ((List) -> Void)? = nil) -> UIViewController {
        let listCount = NSManagedObject.fetchRequest(List.self, limit: 1)
        if try! PersistentStoreManager.container.viewContext.count(for: listCount) > 0 {
            let rootAddToList = UIStoryboard.AddToList.instantiateRoot(withStyle: .formSheet) as! UINavigationController
            let addToList = (rootAddToList.viewControllers[0] as! AddToList)
            addToList.books = booksToAdd
            addToList.onCompletion = completion
            return rootAddToList
        } else {
            return AddToList.newListAlertController(booksToAdd, completion: completion)
        }
    }

    static func newListAlertController(_ books: [Book], completion: ((List) -> Void)? = nil) -> UIAlertController {
        let existingListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)

        func textValidator(listName: String?) -> Bool {
            guard let listName = listName, !listName.isEmptyOrWhitespace else { return false }
            return !existingListNames.contains(listName)
        }

        return TextBoxAlertController(title: "Add New List", message: "Enter a name for your list", placeholder: "Enter list name",
                                      keyboardAppearance: UserDefaults.standard[.theme].keyboardAppearance, textValidator: textValidator) { title in
            let createdList = List(context: PersistentStoreManager.container.viewContext, name: title!)
            createdList.books = NSOrderedSet(array: books)
            PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
            completion?(createdList)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 40)
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.name)]
        resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        try! resultsController.performFetch()

        monitorThemeSetting()
    }

    @IBAction private func cancelWasPressed(_ sender: Any) { navigationController!.dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == addNewListSectionIndex { return 1 }
        return resultsController.fetchedObjects!.count
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        // One "Add new" section, one "existing" section
        return 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == addNewListSectionIndex { return "Add to a new list" }
        return "Or add to an existing list"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = indexPath.section == addNewListSectionIndex ? "NewListCell" : "ExistingListCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        cell.defaultInitialise(withTheme: UserDefaults.standard[.theme])

        if indexPath.section == addNewListSectionIndex {
            cell.textLabel!.text = "Add New List"
            cell.accessoryType = .disclosureIndicator
        } else {
            let listObj = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
            cell.textLabel!.text = listObj.name
            cell.detailTextLabel!.text = "\(listObj.books.count) book\(listObj.books.count == 1 ? "" : "s")"
            cell.isEnabled = true

            // If any of the books are already in this list:
            // FUTURE: Check whether this is firing a lot of faults
            let booksInThisList = listObj.books.set
            if booksSet.intersects(booksInThisList) {
                let alreadyAddedText: String
                if booksSet.isSubset(of: booksInThisList) {
                    alreadyAddedText = books.count == 1 ? "already added" : "all already added"
                    cell.isEnabled = false
                } else {
                    let overlapSet = booksSet.mutableCopy() as! NSMutableSet
                    overlapSet.intersect(booksInThisList)
                    alreadyAddedText = "\(overlapSet.count) already added"
                }

                cell.detailTextLabel!.text?.append(" (\(alreadyAddedText))")
            }
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == addNewListSectionIndex {
            present(AddToList.newListAlertController(books) { [unowned self] list in
                self.navigationController?.dismiss(animated: true) { [unowned self] in
                    self.onCompletion?(list)
                }
            }, animated: true)
        } else {
            // Append the books to the end of the selected list
            let list = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
            list.managedObjectContext!.performAndSave {
                list.addBooks(NSOrderedSet(array: self.books))
            }

            navigationController?.dismiss(animated: true) { [unowned self] in
                self.onCompletion?(list)
            }
        }
    }
}
