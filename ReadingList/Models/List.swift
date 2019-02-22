import Foundation
import CoreData

@objc(List)
public class List: NSManagedObject {
    @NSManaged public var name: String
    @NSManaged public var books: NSOrderedSet
    @NSManaged public var order: BookSort
    @NSManaged public var sort: Int32

    @NSManaged func addBooks(_: NSOrderedSet)
    @NSManaged func removeBooks(_: NSSet)

    convenience init(context: NSManagedObjectContext, name: String) {
        self.init(context: context)
        self.name = name
        if let maxSort = List.maxSort(fromContext: context) {
            self.sort = maxSort + 1
        }
    }

    static func names(fromContext context: NSManagedObjectContext) -> [String] {
        let fetchRequest = NSManagedObject.fetchRequest(List.self)
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.sort), NSSortDescriptor(\List.name)]
        fetchRequest.returnsObjectsAsFaults = false
        return (try! context.fetch(fetchRequest)).map { $0.name }
    }

    static func maxSort(fromContext context: NSManagedObjectContext) -> Int32? {
        let fetchRequest = NSManagedObject.fetchRequest(List.self, limit: 1)
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.sort, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        let result = try! context.fetch(fetchRequest)
        if let firstResult = result.first {
            return firstResult.sort
        } else {
            return nil
        }
    }
}
