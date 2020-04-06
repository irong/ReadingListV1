import Foundation
import CoreData
import UIKit

public protocol UITableViewEmptyDetectingDataSource: UITableViewDataSource {
    var emptyDetectionDelegate: UITableViewEmptyDetectingDataSourceDelegate? { get set }
}

public protocol UITableViewEmptyDetectingDataSourceDelegate: class {
    func tableDidBecomeEmpty()
    func tableDidBecomeNonEmpty()
}

@available(iOS 13.0, *) //swiftlint:disable:next generic_type_name
open class EmptyDetectingTableDiffableDataSource<SectionIdentifierType, ItemIdentifierType>: UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>, UITableViewEmptyDetectingDataSource where SectionIdentifierType: Hashable, ItemIdentifierType: Hashable {
    public weak var emptyDetectionDelegate: UITableViewEmptyDetectingDataSourceDelegate?
    var isEmpty = false

    public override init(tableView: UITableView, cellProvider: @escaping UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider) {
        super.init(tableView: tableView, cellProvider: cellProvider)
    }

    override public func apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
        if snapshot.numberOfItems == 0 {
            if !isEmpty {
                emptyDetectionDelegate?.tableDidBecomeEmpty()
                isEmpty = true
            }
        } else if isEmpty {
            emptyDetectionDelegate?.tableDidBecomeNonEmpty()
            isEmpty = false
        }
        super.apply(snapshot, animatingDifferences: animatingDifferences, completion: completion)
    }
}

public protocol UITableViewDataSourceFetchedResultsControllerDelegate: UITableViewDataSource, NSFetchedResultsControllerDelegate {
    var tableView: UITableView { get }
}

extension UITableViewDataSourceFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}

/// A UITableViewController that monitors calls to the numberOfSections and numberOfRows function calls, to determine when a
/// table has become empty, and switches out a background view accordingly.
open class LegacyEmptyDetectingTableDataSource: NSObject, UITableViewEmptyDetectingDataSource {
    public weak var emptyDetectionDelegate: UITableViewEmptyDetectingDataSourceDelegate?
    public let tableView: UITableView

    public private(set) var isEmpty = false
    private var hasPerformedInitialLoad = false
    private var cachedNumberOfSections = 0
    private let emptyStateView = EmptyStateView()

    public init(_ tableView: UITableView) {
        self.tableView = tableView
    }

    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        fatalError("tableView:cellForRowAt: must be overriden")
    }

    final public func numberOfSections(in tableView: UITableView) -> Int {
        cachedNumberOfSections = sectionCount(in: tableView)
        if cachedNumberOfSections == 0 {
            if !isEmpty {
                emptyDetectionDelegate?.tableDidBecomeEmpty()
                isEmpty = true
            }
        } else if isEmpty {
            emptyDetectionDelegate?.tableDidBecomeNonEmpty()
            isEmpty = false
        }

        return cachedNumberOfSections
    }

    final public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // We want to treat a 1-section, 0-row table as empty.
        let rowCount = self.rowCount(in: tableView, forSection: section)
        if !isEmpty {
            if cachedNumberOfSections == 1 && section == 0 && rowCount == 0 {
                emptyDetectionDelegate?.tableDidBecomeEmpty()
                isEmpty = true
            }
        } else {
            if cachedNumberOfSections != 1 || section != 0 || rowCount != 0 {
                emptyDetectionDelegate?.tableDidBecomeNonEmpty()
                isEmpty = false
            }
        }
        return rowCount
    }

    open func sectionCount(in tableView: UITableView) -> Int {
        fatalError("sectionCount(in:) is not overridden")
    }

    open func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        fatalError("rowCount(in:forSection:) is not overridden")
    }
}

open class UITableViewEmptyStateManager: UITableViewEmptyDetectingDataSourceDelegate {
    let tableView: UITableView
    private let emptyStateView = EmptyStateView()
    public var isShowingEmptyState = false

    public init(_ tableView: UITableView) {
        self.tableView = tableView
    }

    public func tableDidBecomeEmpty() {
        showEmptyDataSet()
        emptyStateDidChange()
    }

    public func tableDidBecomeNonEmpty() {
        hideEmptyDataSet()
        emptyStateDidChange()
    }

    public final func showEmptyDataSet() {
        tableView.isScrollEnabled = false
        reloadEmptyStateView()
        tableView.backgroundView = emptyStateView
        isShowingEmptyState = true
    }

    public final func hideEmptyDataSet() {
        tableView.backgroundView = nil
        tableView.isScrollEnabled = true
        isShowingEmptyState = false
    }

    public final func reloadEmptyStateView() {
        emptyStateView.title.attributedText = titleForEmptyState()
        emptyStateView.text.attributedText = textForEmptyState()
        emptyStateView.position = positionForEmptyState()
    }

    open func titleForEmptyState() -> NSAttributedString {
        return NSAttributedString(string: "Empty State")
    }

    open func textForEmptyState() -> NSAttributedString {
        return NSAttributedString(string: "To customise the text displayed, override titleForEmptyState() and textForEmptyState().")
    }

    open func positionForEmptyState() -> EmptyStatePosition {
        return .center
    }

    open func emptyStateDidChange() { }
}
