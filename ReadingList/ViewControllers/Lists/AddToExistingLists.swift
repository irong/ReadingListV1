import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

class AddToExistingLists: UITableViewController {
    var resultsController: NSFetchedResultsController<List>!
    var onComplete: (() -> Void)?
    var books: Set<Book>!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !books.isEmpty else { preconditionFailure() }

        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 40)
        fetchRequest.predicate = NSPredicate.or(books.map {
            NSPredicate(format: "SELF IN %@", $0.lists).not()
        })
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.sort), NSSortDescriptor(\List.name)]
        resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        resultsController.delegate = tableView
        try! resultsController.performFetch()

        monitorThemeSetting()
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

        if books.count > 1 {
            let overlapCount = getBookListOverlap(list)
            if overlapCount > 0 {
                cell.detailTextLabel!.text?.append(" (\(overlapCount) already added)")
            }
        }
        return cell
    }

    private func getBookListOverlap(_ list: List) -> Int {
        let listBooks = list.books.set
        let overlapSet = (books as NSSet).mutableCopy() as! NSMutableSet
        overlapSet.intersect(listBooks)
        return overlapSet.count
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Append the books to the end of the selected list
        let list = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
        list.managedObjectContext!.performAndSave {
            list.addBooks(NSOrderedSet(set: self.books))
        }
        navigationController?.dismiss(animated: true, completion: onComplete)
        UserEngagement.logEvent(.addBookToList)
    }
}
