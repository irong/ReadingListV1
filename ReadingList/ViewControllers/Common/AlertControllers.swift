import Foundation
import UIKit
import DZNEmptyDataSet
import Eureka
import ImageRow

extension UIAlertController {
    static func duplicateBook(goToExistingBook: @escaping () -> Void, cancel: @escaping () -> Void) -> UIAlertController {

        let alert = UIAlertController(title: "Book Already Added", message: "A book with the same ISBN or Google Books ID has already been added to your reading list.", preferredStyle: .alert)

        // "Go To Existing Book" option - dismiss the provided ViewController (if there is one), and then simulate the book selection
        alert.addAction(UIAlertAction(title: "Go To Existing Book", style: .default) { _ in
            goToExistingBook()
        })

        // "Cancel" should just envoke the callback
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            cancel()
        })

        return alert
    }

    static func selectOrder(_ orderable: Orderable, onChange: @escaping () -> Void) -> UIAlertController {
        return selectOption(BookSort.allCases, title: "Choose Order", selected: orderable.getSort()) { sortOrder in
            orderable.setSort(sortOrder)
            onChange()
        }
    }

    static func selectOption<Option>(_ options: [Option], title: String, selected: Option, _ onChange: @escaping (Option) -> Void) -> UIAlertController where Option: CustomStringConvertible, Option: Equatable {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for option in options {
            let title = selected == option ? "  \(option.description) ✓" : option.description
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                if selected == option { return }
                onChange(option)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        return alert
    }
}

enum Orderable {
    case book(BookReadState)
    case list(List)

    func supports(_ sort: BookSort) -> Bool {
        switch self {
        case let .book(readState):
            return sort.supports(readState)
        case .list:
            return sort.supportsListSorting
        }
    }

    func getSort() -> BookSort {
        switch self {
        case let .book(readState):
            let setting = UserSettingsCollection.sortSetting(for: readState)
            return UserDefaults.standard[setting]
        case let .list(list):
            return list.order
        }
    }

    func setSort(_ order: BookSort) {
        switch self {
        case let .book(readState):
            let setting = UserSettingsCollection.sortSetting(for: readState)
            UserDefaults.standard[setting] = order
        case let .list(list):
            list.order = order
            list.managedObjectContext!.saveAndLogIfErrored()
        }
    }
}
