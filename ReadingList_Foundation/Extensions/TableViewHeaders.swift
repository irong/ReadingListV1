import Foundation
import UIKit

public protocol HeaderConfigurable where Self: UITableViewController {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int)
}

public extension HeaderConfigurable {
    func reloadHeaders() {
        for index in 0..<numberOfSections(in: tableView) {
            guard let header = tableView.headerView(forSection: index) else { continue }
            configureHeader(header, at: index)
        }
    }
}
