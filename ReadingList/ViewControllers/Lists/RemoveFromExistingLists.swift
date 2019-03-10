import Foundation
import UIKit

class RemoveFromExistingLists: UITableViewController {
    var book: Book!
    var sortedLists: [List]!

    override func viewDidLoad() {
        super.viewDidLoad()
        cacheSortedLists()
        setEditing(true, animated: false)
    }

    private func cacheSortedLists() {
        sortedLists = book.lists.sorted {
            if $0.sort == $1.sort { return $0.name.compare($1.name) == .orderedAscending }
            return $0.sort < $1.sort
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedLists.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExistingListCell", for: indexPath)
        cell.defaultInitialise(withTheme: UserDefaults.standard[.theme])

        let list = sortedLists[indexPath.row]
        cell.textLabel!.text = list.name
        cell.detailTextLabel!.text = "\(list.books.count) book\(list.books.count == 1 ? "" : "s")"
        return cell
    }

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [UITableViewRowAction(style: .destructive, title: "Remove", color: .red) { _, indexPath in
            let list = self.sortedLists[indexPath.row]
            list.removeBooks(NSSet(object: self.book))
            self.cacheSortedLists()
            list.managedObjectContext!.saveAndLogIfErrored()
            self.tableView.deleteRows(at: [indexPath], with: .automatic)
            if self.book.lists.isEmpty {
                self.navigationController?.popViewController(animated: true)
            }
        }]
    }
}
