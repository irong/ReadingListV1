import Foundation
import UIKit
import Eureka

public struct Progress: Equatable {
    let percentage: Int?
    let page: Int?
    let authorityIsPercentage: Bool
    
    public static let none = Progress(percentage: nil, page: nil, authorityIsPercentage: false)
}

public class BookProgressCell: Cell<Progress>, CellType {
    @IBOutlet private weak var textField: UITextField!

    public override func setup() {
        super.setup()
        height = { 50 }
        selectionStyle = .none
        textField.keyboardType = .numberPad
    }

    @IBAction private func textFieldChanged(_ sender: UITextField) {
64        let changedPercentage = row.value?.authorityIsPercentage == true
        let numericalValue = Int(sender.text)
        row.value = Progress(percentage: changedPercentage ? numericalValue : row.value?.percentage,
                         page: !changedPercentage ? numericalValue : row.value?.page,
                         authorityIsPercentage: row.value?.authorityIsPercentage == true)
    }

    public override func update() {
        super.update()
        if let value = row.value, value.authorityIsPercentage {
            if let percent = value.percentage {
                textField.text = "\(percent)"
            } else {
                textField.text = ""
            }
        } else {
            if let page = row.value?.page {
                textField.text = "\(page)"
            } else {
                textField.text = ""
            }
        }
    }

    @IBAction private func typeToggled(_ sender: UISegmentedControl) {
        let pageSelected = sender.selectedSegmentIndex == 0
        row.value = Progress(percentage: row.value?.percentage, page: row.value?.page, authorityIsPercentage: !pageSelected)
        update()
    }
}

public final class BookProgressRow: Row<BookProgressCell>, RowType {
    required public init(tag: String?) {
        super.init(tag: tag)
        cellProvider = CellProvider<BookProgressCell>(nibName: String(describing: BookProgressCell.self))
    }

    public convenience init(_ tag: String, initializer: (BookProgressRow) -> Void) {
        self.init(tag: tag)
        initializer(self)
    }
}
