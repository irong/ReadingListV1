import Foundation
import CoreData
import UIKit

class ReviewBulkBooks: UITableViewController {

    var books = [Book]()
    var context: NSManagedObjectContext!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        assert(!books.isEmpty)
        tableView.register(BookTableViewCell.self)

        navigationItem.title = "Review \(books.count) \("Book".pluralising(books.count))"

        monitorThemeSetting()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        assert(section == 0)
        return books.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(BookTableViewCell.self, for: indexPath)
        cell.configureFrom(books[indexPath.row])
        return cell
    }
}
