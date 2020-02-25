import Foundation
import UIKit
import CoreData
import os.log
import ReadingList_Foundation

class UITableViewSearchableEmptyStateManager: UITableViewEmptyStateManager {

    let searchController: UISearchController
    let navigationBar: UINavigationBar?
    let navigationItem: UINavigationItem
    let initialLargeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode
    let initialPrefersLargeTitles: Bool

    let emptyStateTitleFont = UIFont.gillSans(forTextStyle: .title1)
    let emptyStateDescriptionFont = UIFont.gillSans(forTextStyle: .title2)
    let emptyStateDescriptionBoldFont = UIFont.gillSansSemiBold(forTextStyle: .title2)

    init(_ tableView: UITableView, navigationBar: UINavigationBar?, navigationItem: UINavigationItem, searchController: UISearchController) {
        self.searchController = searchController
        self.navigationBar = navigationBar
        self.navigationItem = navigationItem
        self.initialLargeTitleDisplayMode = navigationItem.largeTitleDisplayMode
        self.initialPrefersLargeTitles = navigationBar?.prefersLargeTitles ?? false
        super.init(tableView)
    }

    override func emptyStateDidChange() {
        super.emptyStateDidChange()
        if isShowingEmptyState {
            if !searchController.isActive {
                navigationItem.searchController?.searchBar.isHidden = true
                navigationItem.largeTitleDisplayMode = .never
                navigationBar?.prefersLargeTitles = false
            }
        } else {
            navigationItem.searchController?.searchBar.isHidden = false
            navigationItem.largeTitleDisplayMode = initialLargeTitleDisplayMode
            navigationBar?.prefersLargeTitles = initialPrefersLargeTitles
        }
    }

    private func attributeWithThemeColor(_ attributedString: NSAttributedString) -> NSAttributedString {
        if #available(iOS 13.0, *) {
            return attributedString
        } else {
            return attributedString.mutable().attributedWithColor(UserDefaults.standard[.theme].titleTextColor)
        }
    }

    final override func titleForEmptyState() -> NSAttributedString {
        let title: NSAttributedString
        if searchController.hasActiveSearchTerms {
            title = "🔍 No Results".attributedWithFont(emptyStateTitleFont)
        } else {
            title = titleForNonSearchEmptyState().attributedWithFont(emptyStateTitleFont)
        }

        return attributeWithThemeColor(title)
    }

    final override func textForEmptyState() -> NSAttributedString {
        let text: NSAttributedString
        if searchController.hasActiveSearchTerms {
            text = textForSearchEmptyState()
        } else {
            text = textForNonSearchEmptyState()
        }

        return attributeWithThemeColor(text)
    }

    final override func positionForEmptyState() -> EmptyStatePosition {
        if searchController.isActive {
            return .top
        } else {
            return .center
        }
    }

    open func titleForNonSearchEmptyState() -> String {
        fatalError("titleForNonSearchEmptyState() not implemented")
    }

    open func textForNonSearchEmptyState() -> NSAttributedString {
        fatalError("textForNonSearchEmptyState() not implemented")
    }

    open func textForSearchEmptyState() -> NSAttributedString {
        fatalError("textForNonSearchEmptyState() not implemented")
    }
}

// TODO: Delete
class SearchableEmptyStateTableViewDataSource: UITableViewEmptyDetectingLegacyDataSource {

    /// Must be assigned as soon as possible - e.g. during `viewDidLoad()`
    let searchController: UISearchController
    var normalLargeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.automatic
    let emptyStateTitleFont = UIFont.gillSans(forTextStyle: .title1)
    let emptyStateDescriptionFont = UIFont.gillSans(forTextStyle: .title2)
    let emptyStateDescriptionBoldFont = UIFont.gillSansSemiBold(forTextStyle: .title2)
    let navigationItem: UINavigationItem

    init(_ tableView: UITableView, searchController: UISearchController, navigationItem: UINavigationItem, cellProvider: @escaping (IndexPath) -> UITableViewCell) {
        self.navigationItem = navigationItem
        self.searchController = searchController
        super.init(tableView, cellProvider: cellProvider)
    }

//    override func viewDidLoad() {
//        super.viewDidLoad()
//
//        // Start with "never"; we will switch to the desired large title mode when/if we detect items
//        navigationItem.largeTitleDisplayMode = .never
//    }
//
//    override func initialise(withTheme theme: Theme) {
//        super.initialise(withTheme: theme)
//        if isShowingEmptyState {
//            reloadEmptyStateView()
//        }
//    }

    private func attributeWithThemeColor(_ attributedString: NSAttributedString) -> NSAttributedString {
        if #available(iOS 13.0, *) {
            return attributedString
        } else {
            return attributedString.mutable().attributedWithColor(UserDefaults.standard[.theme].titleTextColor)
        }
    }

    //final override func titleForEmptyState() -> NSAttributedString {
    //    let title: NSAttributedString
    //    if searchController.hasActiveSearchTerms {
    //        title = "🔍 No Results".attributedWithFont(emptyStateTitleFont)
    //    } else {
    //        title = titleForNonSearchEmptyState().attributedWithFont(emptyStateTitleFont)
    //    }
//
    //    return attributeWithThemeColor(title)
    //}
//
    //final override func textForEmptyState() -> NSAttributedString {
    //    let text: NSAttributedString
    //    if searchController.hasActiveSearchTerms {
    //        text = textForSearchEmptyState()
    //    } else {
    //        text = textForNonSearchEmptyState()
    //    }
//
    //    return attributeWithThemeColor(text)
    //}
//
    //final override func positionForEmptyState() -> EmptyStatePosition {
    //    if searchController.isActive {
    //        return .top
    //    } else {
    //        return .center
    //    }
    //}

    func titleForNonSearchEmptyState() -> String {
        fatalError("titleForNonSearchEmptyState() not implemented")
    }

    func textForNonSearchEmptyState() -> NSAttributedString {
        fatalError("textForNonSearchEmptyState() not implemented")
    }

    func textForSearchEmptyState() -> NSAttributedString {
        fatalError("textForNonSearchEmptyState() not implemented")
    }

    func configureNavigationBarButtons() { }

    func updateEmptyStateRelatedItems() {
        if isEmpty {
            if !searchController.isActive {
                navigationItem.searchController = nil
                navigationItem.largeTitleDisplayMode = .never
            }
        } else {
            navigationItem.largeTitleDisplayMode = normalLargeTitleDisplayMode
            navigationItem.searchController = searchController
        }

        configureNavigationBarButtons()
    }

    func searchWillBeDismissed() {
        // Schedule a call to update the other bits of UI when the search controller is being dismissed. We do this so
        // that we can properly reflect the inactive state of the search controller (it will only be inactive at the end
        // of this main run-loop). Some UI depends on whether the search controller is active; hence the need to rerun the update,
        // even if we are going from empty --> empty.
        DispatchQueue.main.async {
            self.updateEmptyStateRelatedItems()
            if self.isEmpty {
                //TODO//self.reloadEmptyStateView()
            }
        }
    }
}
