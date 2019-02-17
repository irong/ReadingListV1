import Foundation
import CoreData

@objc(List)
public class List: NSManagedObject {
    @NSManaged var name: String
    @NSManaged var books: NSOrderedSet
    @NSManaged var order: BookSort

    convenience init(context: NSManagedObjectContext, name: String) {
        self.init(context: context)
        self.name = name
    }

    static func getOrCreate(fromContext context: NSManagedObjectContext, withName name: String) -> List {
        let listFetchRequest = NSManagedObject.fetchRequest(List.self, limit: 1)
        listFetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(List.name), name)
        listFetchRequest.returnsObjectsAsFaults = false
        if let existingList = (try! context.fetch(listFetchRequest)).first {
            return existingList
        }
        return List(context: context, name: name)
    }

    @NSManaged func addBooks(_: NSOrderedSet)
    @NSManaged func removeBooks(_: NSSet)

    static func names(fromContext context: NSManagedObjectContext) -> [String] {
        let fetchRequest = NSManagedObject.fetchRequest(List.self)
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.name)]
        fetchRequest.returnsObjectsAsFaults = false
        return (try! context.fetch(fetchRequest)).map { $0.name }
    }
}
