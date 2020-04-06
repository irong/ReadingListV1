import UIKit
import CoreData

@available(iOS 13.0, *)
public protocol FetchedResultsControllerChangeProcessorDelegate: class {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeProducingSnapshot snapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>)
}

@available(iOS 13.0, *)
public extension NSFetchedResultsController {

    /**
     Generates a `NSDiffableDataSourceSnapshot` where the section identifiers are the fetched section names, and the item identifiers are the fetched object's `NSManagedObjectID`.
     */
    @objc func snapshot() -> NSDiffableDataSourceSnapshot<String, NSManagedObjectID> {
        guard let sections = sections else { preconditionFailure("Controller sections info was nil: a fetch must be performed before calling `snapshot()`") }

        var snapshot = NSDiffableDataSourceSnapshot<String, NSManagedObjectID>()
        snapshot.appendSections(sections.map(\.name))
        for section in sections {
            guard let objects = section.objects else { preconditionFailure() }
            snapshot.appendItems(objects.map { $0 as! NSManagedObject }.map(\.objectID), toSection: section.name)
        }
        return snapshot
    }
}

@available(iOS 13.0, *)
public extension NSDiffableDataSourceSnapshot {
    mutating func incoporateSectionChange(_ change: CollectionDifference<SectionIdentifierType>.Change) {
        switch change {
        case .insert(offset: sectionIdentifiers.count, let element, _):
            // If the offset is such that it places this item at the end of collection, append it
            appendSections([element])
        case .insert(let offset, let element, _):
            // Otherwise, insert the new item before the item which is currently at the desired position
            let existingSection = sectionIdentifiers[offset]
            insertSections([element], beforeSection: existingSection)
        case .remove(_, let element, _):
            deleteSections([element])
        }
    }

    mutating func incoporateItemChange(_ change: CollectionDifference<ItemIdentifierType>.Change, inSection section: SectionIdentifierType) {
        switch change {
        case .insert(itemIdentifiers(inSection: section).count, let element, _):
            // If the offset is such that it places this item at the end of collection, append it
            appendItems([element], toSection: section)
        case .insert(let offset, let element, _):
            // Otherwise, insert the new item before the item which is currently at the desired position
            let existingItem = itemIdentifiers(inSection: section)[offset]
            insertItems([element], beforeItem: existingItem)
        case .remove(_, let element, _):
            deleteItems([element])
        }
    }
}

/**
 Processes changes reported by a NSFetchedResultsController to a diffable data source.
 */
@available(iOS 13.0, *)
public final class FetchedResultsControllerChangeProcessor: NSObject, NSFetchedResultsControllerDelegate {

    public weak var delegate: FetchedResultsControllerChangeProcessorDelegate?
    let getCurrentSnapshot: () -> NSDiffableDataSourceSnapshot<String, NSManagedObjectID>

    public init(getCurrentSnapshot: @escaping () -> NSDiffableDataSourceSnapshot<String, NSManagedObjectID>) {
        self.getCurrentSnapshot = getCurrentSnapshot
    }

    // We cannot keep track of the changes in a DiffableDataSourceSnapshot unfortunately, as the changes may come in in an order
    // which we do not support. For example, it may notify us of new inserts at large indices before inserts at smaller indices.
    // Hence, accumulate all the changes here; when they are all loaded, we will build a new snapshot.
    private var changeProcessingSnapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>!
    private var sectionChanges = [CollectionDifference<String>.Change]()
    private var itemChangesBySection = [String: [CollectionDifference<NSManagedObjectID>.Change]]()
    private var updatedObjects = Set<NSManagedObjectID>()

    public func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        // grab a new snapshot, ready to modfiy
        changeProcessingSnapshot = getCurrentSnapshot()
        itemChangesBySection = [:]
        updatedObjects = Set<NSManagedObjectID>()
    }

    func addItemChange(_ change: CollectionDifference<NSManagedObjectID>.Change, to section: String) {
        if let array = itemChangesBySection[section] {
            itemChangesBySection[section] = array + [change]
        } else {
            itemChangesBySection[section] = [change]
        }
    }

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard let itemID = (anObject as? NSManagedObject)?.objectID else { preconditionFailure() }

        switch type {
        case .insert:
            guard let newIndex = newIndexPath else { preconditionFailure() }
            let sectionName = controller.sections![newIndex.section].name
            addItemChange(.insert(offset: newIndex.row, element: itemID, associatedWith: nil), to: sectionName)
        case .move:
            guard let oldIndex = indexPath, let newIndex = newIndexPath else { preconditionFailure() }
            let isSameSection = oldIndex.section != newIndex.section
            if !isSameSection {
                assertionFailure("HEY LOOK, Move can move between sections!")
            }

            let oldSection = controller.sections![oldIndex.section].name
            let newSection = controller.sections![newIndex.section].name

            updatedObjects.insert(itemID)
            addItemChange(.insert(offset: newIndex.row, element: itemID, associatedWith: isSameSection ? oldIndex.row : nil), to: newSection)
            addItemChange(.remove(offset: oldIndex.row, element: itemID, associatedWith: isSameSection ? newIndex.row : nil), to: oldSection)
        case .update:
            updatedObjects.insert(itemID)
        case .delete:
            guard let oldIndex = indexPath else { preconditionFailure() }
            let oldSection = controller.sections![oldIndex.section].name
            addItemChange(.remove(offset: oldIndex.row, element: itemID, associatedWith: nil), to: oldSection)
        @unknown default:
            assertionFailure("Unhandled \(NSFetchedResultsChangeType.self) \(type)")
        }
    }

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            sectionChanges.append(.insert(offset: sectionIndex, element: sectionInfo.name, associatedWith: nil))
        case .delete:
            sectionChanges.append(.remove(offset: sectionIndex, element: sectionInfo.name, associatedWith: nil))
        default:
            preconditionFailure()
        }
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {

        // First handle the section changes
        guard let sectionChangeCollection = CollectionDifference(sectionChanges) else {
            preconditionFailure("Unable to create a collection difference from the changes \(itemChangesBySection)")
        }
        for change in sectionChangeCollection {
            changeProcessingSnapshot.incoporateSectionChange(change)
        }

        // Then, for each section which has item changes, handle the item changes
        for (section, rowChanges) in itemChangesBySection {
            guard let rowChangeCollection = CollectionDifference(rowChanges) else { preconditionFailure() }
            for change in rowChangeCollection {
                changeProcessingSnapshot.incoporateItemChange(change, inSection: section)
            }
        }

        // Remember to reload the items which have been updated
        changeProcessingSnapshot.reloadItems(Array(updatedObjects))

        // Now we have finished preparing our modified snapshot, notify the delegate of the new snapshot.
        delegate?.controller(controller, didChangeProducingSnapshot: changeProcessingSnapshot)
    }
}
