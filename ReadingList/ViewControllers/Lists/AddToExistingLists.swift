import Foundation
import UIKit
import CoreData

class AddToExistingLists: UITableViewController {
    var resultsController: NSFetchedResultsController<List>!
    var onComplete: (() -> Void)?
    var books: [Book]!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !books.isEmpty else { preconditionFailure() }

        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 40)
        // TODO: Exclude already added lists if book count = 1
        //fetchRequest.predicate = NSPredicate(
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.sort), NSSortDescriptor(\List.name)]
        resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        resultsController.delegate = tableView
        try! resultsController.performFetch()
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
        // TODO: Determine overlap if >1 book specified?
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Append the books to the end of the selected list
        let list = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
        list.managedObjectContext!.performAndSave {
            list.addBooks(NSOrderedSet(array: self.books))
        }
        navigationController?.dismiss(animated: true, completion: onComplete)
    }
}
