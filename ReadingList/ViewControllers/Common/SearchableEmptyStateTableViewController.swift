import Foundation
import UIKit
import os.log
import ReadingList_Foundation

class SearchableEmptyStateTableViewController: EmptyStateTableViewController {

    /// Must be assigned as soon as possible - e.g. during `viewDidLoad()`
    var searchController: UISearchController!
    var normalLargeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.automatic
    let emptyStateTitleFont = UIFont.gillSans(forTextStyle: .title1)
    let emptyStateDescriptionFont = UIFont.gillSans(forTextStyle: .title2)
    let emptyStateDescriptionBoldFont = UIFont.gillSansSemiBold(forTextStyle: .title2)

    override func viewDidLoad() {
        super.viewDidLoad()

        // Start with "never"; we will switch to the desired large title mode when/if we detect items
        navigationItem.largeTitleDisplayMode = .never
    }

    override func initialise(withTheme theme: Theme) {
        super.initialise(withTheme: theme)
        if isShowingEmptyState {
            reloadEmptyStateView()
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
            text = textForSearchEmptyState()
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

    func titleForNonSearchEmptyState() -> String {
        fatalError("titleForNonSearchEmptyState() not implemented")
    }

    func textForNonSearchEmptyState() -> NSAttributedString {
        fatalError("textForNonSearchEmptyState() not implemented")
    }

    func textForSearchEmptyState() -> NSAttributedString {
        fatalError("textForNonSearchEmptyState() not implemented")
    }

    override func tableDidBecomeNonEmpty() {
        updateEmptyStateRelatedItems()
    }

    override func tableDidBecomeEmpty() {
        updateEmptyStateRelatedItems()
    }

    func configureNavigationBarButtons() { }

    func updateEmptyStateRelatedItems() {
        if isShowingEmptyState {
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
        // of this loop). Some UI depends on whether the search controller is active; hence the need to rerun the update,
        // even if we are going from empty --> empty.
        DispatchQueue.main.async {
            self.updateEmptyStateRelatedItems()
            if self.isShowingEmptyState {
                self.reloadEmptyStateView()
            }
        }
    }
}
