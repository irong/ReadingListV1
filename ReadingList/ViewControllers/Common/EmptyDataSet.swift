import Foundation
import UIKit
import DZNEmptyDataSet

extension DZNEmptyDataSetSource {
    var titleFont: UIFont { return UIFont.gillSans(ofSize: 32) }
    var descriptionFont: UIFont { return UIFont.gillSans(forTextStyle: .title2) }
    var boldDescriptionFont: UIFont { return UIFont.gillSansSemiBold(forTextStyle: .title2) }

    func title(_ text: String) -> NSAttributedString {
        let labelColor: UIColor
        if #available(iOS 13.0, *) {
            labelColor = .label
        } else {
            labelColor = UserDefaults.standard[.theme].titleTextColor
        }
        return NSAttributedString(string: text, attributes: [.font: titleFont,
                                                             .foregroundColor: labelColor])
    }

    func applyDescriptionAttributes(_ attributedString: NSMutableAttributedString) -> NSMutableAttributedString {
        let labelColor: UIColor
        if #available(iOS 13.0, *) {
            labelColor = .secondaryLabel
        } else {
            labelColor = UserDefaults.standard[.theme].subtitleTextColor
        }
        attributedString.addAttribute(.foregroundColor, value: labelColor,
                                      range: NSRange(location: 0, length: attributedString.string.count))
        return attributedString
    }

    func noResultsDescription(for entity: String) -> NSAttributedString {
        return applyDescriptionAttributes(
            NSMutableAttributedString("Try changing your search, or add a new \(entity) by tapping the ", font: descriptionFont)
                .appending("+", font: boldDescriptionFont)
                .appending(" button.", font: descriptionFont)
        )
    }
}
