import ReadingList_Foundation

final class BookTableEmptyDataSourceManager: UITableViewSearchableEmptyStateManager {

    let readStates: [BookReadState]
    let onEmptyStateChange: (Bool) -> Void

    init(tableView: UITableView, navigationBar: UINavigationBar?, navigationItem: UINavigationItem, searchController: UISearchController,
         readStates: [BookReadState], onEmptyStateChange: @escaping (Bool) -> Void) {
        self.onEmptyStateChange = onEmptyStateChange
        self.readStates = readStates
        super.init(tableView, navigationBar: navigationBar, navigationItem: navigationItem, searchController: searchController)
    }

    final override func titleForNonSearchEmptyState() -> String {
        if readStates.contains(.reading) {
            return "📚 To Read"
        } else {
            return "🎉 Finished"
        }
    }

    override func textForNonSearchEmptyState() -> NSAttributedString {
        let mutableString: NSMutableAttributedString
        if readStates.contains(.reading) {
            mutableString = NSMutableAttributedString("Books you add to your ", font: emptyStateDescriptionFont)
                .appending("To Read", font: emptyStateDescriptionBoldFont)
                .appending(" list, or mark as currently ", font: emptyStateDescriptionFont)
                .appending("Reading", font: emptyStateDescriptionBoldFont)
                .appending(" will show up here.", font: emptyStateDescriptionFont)
        } else {
            mutableString = NSMutableAttributedString("Books you mark as ", font: emptyStateDescriptionFont)
                .appending("Finished", font: emptyStateDescriptionBoldFont)
                .appending(" will show up here.", font: emptyStateDescriptionFont)
        }

        mutableString.appending("\n\nAdd a book by tapping the ", font: emptyStateDescriptionFont)
            .appending("+", font: emptyStateDescriptionBoldFont)
            .appending(" button above.", font: emptyStateDescriptionFont)

        return mutableString
    }

    override func textForSearchEmptyState() -> NSAttributedString {
        return NSMutableAttributedString(
            "Try changing your search, or add a new book by tapping the ", font: emptyStateDescriptionFont)
        .appending("+", font: emptyStateDescriptionBoldFont)
        .appending(" button.", font: emptyStateDescriptionFont)
    }

    final override func emptyStateDidChange() {
        super.emptyStateDidChange()
        self.onEmptyStateChange(isShowingEmptyState)
    }
}
