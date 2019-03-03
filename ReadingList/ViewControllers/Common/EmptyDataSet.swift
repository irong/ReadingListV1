import Foundation
import UIKit

class StandardEmptyDataset {

    static func title(withText text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [.font: UIFont.gillSans(ofSize: 32),
                                                             .foregroundColor: UserDefaults.standard[.theme].titleTextColor])
    }

    static func description(withMarkdownText markdownText: String) -> NSAttributedString {
        let bodyFont = UIFont.gillSans(forTextStyle: .title2)
        let boldFont = UIFont.gillSansSemiBold(forTextStyle: .title2)

        let markedUpString = NSAttributedString.createFromMarkdown(markdownText, font: bodyFont, boldFont: boldFont)
        markedUpString.addAttribute(.foregroundColor, value: UserDefaults.standard[.theme].subtitleTextColor, range: NSRange(location: 0, length: markedUpString.string.count))
        return markedUpString
    }
}
