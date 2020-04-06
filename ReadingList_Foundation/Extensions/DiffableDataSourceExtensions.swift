import UIKit
import CoreData

@available(iOS 13.0, *)
public extension NSDiffableDataSourceSnapshot {
    /**
     Loads a change within one specific section.
     */
    mutating func loadChange(changedObject object: ItemIdentifierType, at index: Int?, for type: NSFetchedResultsChangeType, newIndex: Int?, inSection section: SectionIdentifierType) {
        switch type {
        case .insert:
            guard let newIndex = newIndex else { preconditionFailure() }
            if !sectionIdentifiers.contains(section) {
                appendSections([section])
            }
            let items = itemIdentifiers(inSection: section)
            if newIndex == items.endIndex + 1 || items.isEmpty {
                appendItems([object], toSection: section)
            } else {
                insertItems([object], beforeItem: items[newIndex])
            }
        case .update:
            reloadItems([object])
        case .move:
            guard let oldIndex = index, let newIndex = newIndex else { preconditionFailure() }
            reloadItems([object])

            let items = itemIdentifiers(inSection: section)
            if items.isEmpty {
                preconditionFailure("Cannot move an item in an empty section")
            }

            if newIndex < oldIndex {
                // ------ X ------------ O --|
                // To move from the O to the X, put the item before the item which is currently in its place
                moveItem(object, beforeItem: items[newIndex])
            } else {
                // ------ O ------------ X --|
                // To move from the O to the X, put the item after the item which is currently in its place
                moveItem(object, afterItem: items[newIndex])
            }
        case .delete:
            deleteItems([object])
            if itemIdentifiers(inSection: section).isEmpty {
                deleteSections([section])
            }
        @unknown default:
            assertionFailure("Unhandled \(NSFetchedResultsChangeType.self) \(type)")
        }
    }

    /**
     Loads a change which can have occurred across sections. Using the source and destination IndexPath (iif applicable), the change will be
     translated into DiffableDataSource identifier movements.
     */
    mutating func loadChange(changedObject object: ItemIdentifierType, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

        switch type {
        case .insert:
            guard let insertionIndex = newIndexPath else { preconditionFailure() }
            let section = sectionIdentifiers[insertionIndex.section]
            let items = itemIdentifiers(inSection: section)
            if insertionIndex.row == items.endIndex + 1 || items.isEmpty {
                appendItems([object], toSection: section)
            } else {
                insertItems([object], beforeItem: items[insertionIndex.row])
            }
        case .update:
            reloadItems([object])
        case .move:
            guard let destinationIndex = newIndexPath else { preconditionFailure() }
            let destinationSection = sectionIdentifiers[destinationIndex.section]
            let destinationSectionItems = itemIdentifiers(inSection: destinationSection)
            if destinationSectionItems.isEmpty {
                // if the destination section is empty, we just delete it from whereever it came from, and append it to this section
                deleteItems([object])
                appendItems([object], toSection: destinationSection)
            } else if destinationIndex.row == destinationSectionItems.startIndex {
                moveItem(object, beforeItem: destinationSectionItems[0])
            } else {
                moveItem(object, afterItem: destinationSectionItems[destinationIndex.row])
            }
        case .delete:
            deleteItems([object])
        @unknown default:
            assertionFailure("Unhandled \(NSFetchedResultsChangeType.self) \(type)")
        }

    }

    mutating func loadChange(changedSection section: SectionIdentifierType, atIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        if type == .delete {
            deleteSections([section])
        } else if type == .insert {
            if sectionIndex == sectionIdentifiers.endIndex + 1 || sectionIdentifiers.isEmpty {
                appendSections([section])
            } else {
                insertSections([section], afterSection: sectionIdentifiers[sectionIndex])
            }
        } else {
            assertionFailure()
        }
    }
}
