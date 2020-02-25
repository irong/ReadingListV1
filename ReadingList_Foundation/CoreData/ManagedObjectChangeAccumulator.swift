import UIKit
import CoreData

@available(iOS 13.0, *)
public final class ManagedObjectChangeAccumulator<Object: NSManagedObject>: NSObject {

    private var transientChanges: [CollectionDifference<Object>.Change] = []
    private var updatedObjects: Set<Object> = []

    public func clearAll() {
        transientChanges.removeAll()
        updatedObjects.removeAll()
    }

    public func loadChange(changedObject anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard let object = anObject as? Object else { return }

        switch type {
        case .insert:
            guard let insertionIndex = newIndexPath else { preconditionFailure() }
            transientChanges.append(.insert(offset: insertionIndex.row, element: object, associatedWith: nil))
        case .update:
            updatedObjects.insert(object)
        case .move:
            guard let sourceIndex = indexPath?.row, let destinationIndex = newIndexPath?.row else { preconditionFailure() }
            updatedObjects.insert(object)
            transientChanges.append(.insert(offset: destinationIndex, element: object, associatedWith: sourceIndex))
            transientChanges.append(.remove(offset: sourceIndex, element: object, associatedWith: destinationIndex))
        case .delete:
            guard let deletedIndex = indexPath?.row else { preconditionFailure() }
            transientChanges.append(.remove(offset: deletedIndex, element: object, associatedWith: nil))
        @unknown default:
            assertionFailure("Unhandled \(NSFetchedResultsChangeType.self) \(type)")
        }
    }

    public func applyChangesToSnapshot<T: Hashable>(initialSnapshot: NSDiffableDataSourceSnapshot<T, Object>) -> NSDiffableDataSourceSnapshot<T, Object> {
        guard let collectionDifference = CollectionDifference(transientChanges) else {
            preconditionFailure("Unable to create a collection difference from the changes \(transientChanges)")
        }

        var snapshotToApplyTo = initialSnapshot
        for change in collectionDifference {
            switch change {
            case .insert(let index, let object, _):
                let identifiers = snapshotToApplyTo.itemIdentifiers(inSection: initialSnapshot.sectionIdentifiers[0])
                if index == identifiers.endIndex || identifiers.isEmpty {
                    snapshotToApplyTo.appendItems([object])
                } else {
                    snapshotToApplyTo.insertItems([object], beforeItem: identifiers[index])
                }
            case .remove(_, let object, _):
                snapshotToApplyTo.deleteItems([object])
            }
        }

        snapshotToApplyTo.reloadItems(Array(updatedObjects))
        return snapshotToApplyTo
    }
}
