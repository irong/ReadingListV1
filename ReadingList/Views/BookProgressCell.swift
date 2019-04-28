import Foundation
import UIKit
import Eureka

public struct Progress: Equatable {
    let percentage: Int?
    let page: Int?
    let authorityIsPercentage: Bool
}

public class BookProgressCell: Cell<Progress>, CellType {
    @IBOutlet private weak var textField: UITextField!
    public var value = Progress(percentage: nil, page: nil, authorityIsPercentage: false) {
        didSet { update() }
    }

    public override func setup() {
        super.setup()
        height = { 50 }
        selectionStyle = .none
        textField.keyboardType = .numberPad
    }

    @IBAction func textFieldEdited(_ sender: UITextField) {
    
        let changedPercentage = value.authorityIsPercentage
        let numericalValue = Int(sender.text)
        value = Progress(percentage: changedPercentage ? numericalValue : value.percentage , page: !changedPercentage ? numericalValue : value.page, authorityIsPercentage: value.authorityIsPercentage)
    }

    public override func update() {
        super.update()
        if value.authorityIsPercentage {
            if let percent = value.percentage {
                textField.text = "\(percent)"
            } else {
                textField.text = ""
            }
        } else {
            if let page = value.page {
                textField.text = "\(page)"
            } else {
                textField.text = ""
            }
        }
    }

    @IBAction func typeToggled(_ sender: UISegmentedControl) {
        let pageSelected = sender.selectedSegmentIndex == 0
        value = Progress(percentage: value.percentage, page: value.page, authorityIsPercentage: !pageSelected)
    }
}

public final class BookProgressRow: Row<BookProgressCell>, RowType {
    required public init(tag: String?) {
        super.init(tag: tag)
        cellProvider = CellProvider<BookProgressCell>(nibName: String(describing: BookProgressCell.self))
    }
}
