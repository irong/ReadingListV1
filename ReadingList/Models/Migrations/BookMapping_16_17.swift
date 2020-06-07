import Foundation
import CoreData

class BookMapping_16_17: NSEntityMigrationPolicy { //swiftlint:disable:this type_name

    //FUNCTION($entityPolicy, "destinationListItemsForSourceList:manager:" , $source.list, $manager)
    @objc func destinationListItems(forSourceList list: NSManagedObject, manager: NSMigrationManager) -> [NSManagedObject] {
        guard let books = list.value(forKey: "books") else { return [] }
        guard let booksSet = books as? NSOrderedSet else { preconditionFailure("Object at key 'books' was not an NSOrderedSet") }
        guard let migratedList = manager.destinationInstances(forEntityMappingName: "ListToList", sourceInstances: [list]).first else {
            preconditionFailure("No migrated List object returned from ListToList entity mapping")
        }

        // Ensure that we preserve the order of the books by looping through the IDs of the books in the order
        // that they appear in the set.
        let orderedBookIds = booksSet.array.map { $0 as! NSManagedObject }.map(\.objectID)
        return orderedBookIds.enumerated().map { index, bookId in
            // Since Books have been migrated prior to this List migration, we can just ask for the desination book with the given ID
            let book = manager.destinationContext.object(with: bookId)
            let listBook = NSEntityDescription.insertNewObject(forEntityName: "ListItem", into: manager.destinationContext)
            listBook.setValue(index, forKey: "sort")
            listBook.setValue(book, forKey: "book")
            listBook.setValue(migratedList, forKey: "list")
            return listBook
        }
    }
}
