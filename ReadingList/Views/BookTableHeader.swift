import Foundation
import UIKit

class BookTableHeader: UITableViewHeaderFooterView {

    @IBOutlet private weak var label: UILabel!
    @IBOutlet private(set) weak var sortButton: UIButton! //swiftlint:disable:this private_outlet
    @IBAction private func sortButtonTapped(_ sender: UIButton) {
        sortTapped(readState)
    }

    var readState = BookReadState.toRead

    func configure(readState: BookReadState, bookCount: Int) {
        label.text = "\(readState.description.uppercased()) (\(bookCount))"
        self.readState = readState
    }

    var sortTapped: (BookReadState) -> Void = { _ in
        assertionFailure()
    }

    func initialise(withTheme theme: Theme) {
        label.textColor = theme.subtitleTextColor
        sortButton.tintColor = theme.subtitleTextColor
    }
}
