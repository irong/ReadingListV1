import Foundation
import UIKit

/// A UITableViewController that monitors calls to the numberOfSections and numberOfRows function calls, to determine when a
/// table has become empty, and switches out a background view accordingly.
open class EmptyStateTableViewController: UITableViewController {
    public private(set) var isShowingEmptyState = false
    private var hasPerformedInitialLoad = false
    private var cachedNumberOfSections = 0
    private let emptyStateView = EmptyStateView()

    final override public func numberOfSections(in tableView: UITableView) -> Int {
        cachedNumberOfSections = sectionCount(in: tableView)
        if cachedNumberOfSections == 0 {
            if !isShowingEmptyState {
                showEmptyDataSet()
                tableDidBecomeEmpty()
            }
        } else if isShowingEmptyState {
            hideEmptyDataSet()
            tableDidBecomeNonEmpty()
        } else if !hasPerformedInitialLoad {
            // We treat an initial load of an empty table as the table "becoming non-empty"
            hasPerformedInitialLoad = true
            tableDidBecomeNonEmpty()
        }

        return cachedNumberOfSections
    }

    final override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // We want to treat a 1-section, 0-row table as empty.
        let rowCount = self.rowCount(in: tableView, forSection: section)
        if !isShowingEmptyState {
            if cachedNumberOfSections == 1 && section == 0 && rowCount == 0 {
                showEmptyDataSet()
                tableDidBecomeEmpty()
            }
        } else {
            if cachedNumberOfSections != 1 || section != 0 || rowCount != 0 {
                hideEmptyDataSet()
                tableDidBecomeNonEmpty()
            }
        }
        return rowCount
    }

    private final func showEmptyDataSet() {
        tableView.isScrollEnabled = false
        reloadEmptyStateView()
        tableView.backgroundView = emptyStateView
        isShowingEmptyState = true
    }

    private final func hideEmptyDataSet() {
        tableView.backgroundView = nil
        tableView.isScrollEnabled = true
        isShowingEmptyState = false
    }

    public final func reloadEmptyStateView() {
        emptyStateView.title.attributedText = titleForEmptyState()
        emptyStateView.text.attributedText = textForEmptyState()
        emptyStateView.position = positionForEmptyState()
    }

    open func sectionCount(in tableView: UITableView) -> Int {
        fatalError("sectionCount(in:) is not overridden")
    }

    open func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        fatalError("rowCount(in:forSection:) is not overridden")
    }

    open func tableDidBecomeEmpty() { }

    open func tableDidBecomeNonEmpty() { }

    open func titleForEmptyState() -> NSAttributedString {
        return NSAttributedString(string: "Empty State")
    }

    open func textForEmptyState() -> NSAttributedString {
        return NSAttributedString(string: "To customise the text displayed, override titleForEmptyState() and textForEmptyState().")
    }

    open func positionForEmptyState() -> EmptyStatePosition {
        return .center
    }
}
