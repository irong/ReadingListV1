import Foundation
import UIKit

class BookTableHeader: UITableViewHeaderFooterView {

    var orderable: Orderable!
    weak var presenter: UITableViewController!
    var onSortChanged: (() -> Void)!

    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var sortButton: UIButton!

    @IBAction private func sortButtonTapped(_ sender: UIButton) {
        let alert = UIAlertController.selectOrder(orderable) { [unowned self] in
            self.onSortChanged()
        }
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sortButton
            popover.sourceRect = sortButton.bounds
        }
        presenter.present(alert, animated: true, completion: nil)
    }

    func configure(readState: BookReadState, bookCount: Int, enableSort: Bool) {
        label.text = "\(readState.description.uppercased()) (\(bookCount))"
        orderable = .book(readState)
        sortButton.isEnabled = enableSort
        initialise(withTheme: UserDefaults.standard[.theme])
    }

    func configure(list: List, bookCount: Int, enableSort: Bool) {
        label.text = "\(bookCount) BOOK\(bookCount == 1 ? "" : "S")"
        orderable = .list(list)
        sortButton.isEnabled = enableSort
        initialise(withTheme: UserDefaults.standard[.theme])
    }

    private func initialise(withTheme theme: Theme) {
        label.textColor = theme.subtitleTextColor
        sortButton.tintColor = theme.subtitleTextColor
    }
}
