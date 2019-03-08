import Foundation
import UIKit
import DZNEmptyDataSet

extension DZNEmptyDataSetSource {
    var titleFont: UIFont { return UIFont.gillSans(ofSize: 32) }
    var descriptionFont: UIFont { return UIFont.gillSans(forTextStyle: .title2) }
    var boldDescriptionFont: UIFont { return UIFont.gillSansSemiBold(forTextStyle: .title2) }

    func title(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [.font: titleFont,
                                                             .foregroundColor: UserDefaults.standard[.theme].titleTextColor])
    }

    func applyDescriptionAttributes(_ attributedString: NSMutableAttributedString) -> NSMutableAttributedString {
        attributedString.addAttribute(.foregroundColor, value: UserDefaults.standard[.theme].subtitleTextColor,
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
