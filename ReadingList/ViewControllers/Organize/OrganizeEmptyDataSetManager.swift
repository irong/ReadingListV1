import ReadingList_Foundation

class OrganizeEmptyDataSetManager: UITableViewSearchableEmptyStateManager {
    override func titleForNonSearchEmptyState() -> String {
         return NSLocalizedString("OrganizeEmptyHeader", comment: "")
    }

    override func textForSearchEmptyState() -> NSAttributedString {
        return NSMutableAttributedString("Try changing your search, or add a new list by tapping the ", font: emptyStateDescriptionFont)
                .appending("+", font: emptyStateDescriptionBoldFont)
                .appending(" button.", font: emptyStateDescriptionFont)
    }

    override func textForNonSearchEmptyState() -> NSAttributedString {
        return NSMutableAttributedString(NSLocalizedString("OrganizeInstruction", comment: ""), font: emptyStateDescriptionFont)
            .appending("\n\nTo create a new list, tap the ", font: emptyStateDescriptionFont)
            .appending("+", font: emptyStateDescriptionBoldFont)
            .appending(" button above, or tap ", font: emptyStateDescriptionFont)
            .appending("Manage Lists", font: emptyStateDescriptionBoldFont)
            .appending(" when viewing a book.", font: emptyStateDescriptionFont)
    }
}
