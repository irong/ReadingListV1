import Foundation
import UIKit

class BookTableHeader: UITableViewHeaderFooterView {

    var orderable: Orderable?
    weak var presenter: UITableViewController?
    var onSortButtonTap: ((_ sender: UIButton) -> Void)?
    var onSortChanged: (() -> Void)?

    static let height: CGFloat = 50
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var sortButton: UIButton!

    @IBAction private func sortButtonTapped(_ sender: UIButton) {
        if let onSortButtonTap = onSortButtonTap {
            onSortButtonTap(sender)
        } else if let orderable = orderable, let presenter = presenter {
            let alert = UIAlertController.selectOrder(orderable) { [unowned self] in
                self.onSortChanged?()
            }
            alert.popoverPresentationController?.setButton(sortButton)
            presenter.present(alert, animated: true, completion: nil)
        } else {
            assertionFailure()
        }
    }

    func configure(labelText: String, enableSort: Bool) {
        label.text = labelText
        sortButton.isEnabled = enableSort
        if #available(iOS 13.0, *) { } else {
            initialise(withTheme: UserDefaults.standard[.theme])
        }
    }

    func configure(readState: BookReadState, bookCount: Int, enableSort: Bool) {
        configure(labelText: "\(readState.description.uppercased()) (\(bookCount))", enableSort: enableSort)
        orderable = .book(readState)
    }

    func configure(list: List, bookCount: Int, enableSort: Bool) {
        configure(labelText: "\(bookCount) BOOK\(bookCount == 1 ? "" : "S")", enableSort: enableSort)
        orderable = .list(list)
    }

    private func initialise(withTheme theme: Theme) {
        if #available(iOS 13.0, *) { } else {
            label.textColor = theme.subtitleTextColor
            sortButton.tintColor = theme.subtitleTextColor
        }
    }
}
