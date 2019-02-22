import Foundation
import CoreData
import os.log

public extension NSManagedObject {
    func delete() {
        guard let context = managedObjectContext else {
            assertionFailure("Attempted to delete a book which was not in a context"); return
        }
        context.delete(self)
    }

    func safelySetPrimitiveValue(_ value: Any?, forKey key: String) {
        willChangeValue(forKey: key)
        setPrimitiveValue(value, forKey: key)
        didChangeValue(forKey: key)
    }

    func safelyGetPrimitiveValue(forKey key: String) -> Any? {
        willAccessValue(forKey: key)
        let value = primitiveValue(forKey: key)
        didAccessValue(forKey: key)
        return value
    }

    static func fetchRequest<T: NSManagedObject>(_ type: T.Type, limit: Int? = nil, batch: Int? = nil) -> NSFetchRequest<T> {
        // Apple bug: the following lines do not work when run from a test target
        // let fetchRequest = T.fetchRequest() as! NSFetchRequest<T>
        // let fetchRequest = NSFetchRequest<T>(entityName: type.entity().managedObjectClassName)
        let fetchRequest = NSFetchRequest<T>(entityName: String(describing: type))
        if let limit = limit { fetchRequest.fetchLimit = limit }
        if let batch = batch { fetchRequest.fetchBatchSize = batch }
        return fetchRequest
    }

    func isValidForUpdate() -> Bool {
        do {
            try self.validateForUpdate()
            return true
        } catch {
            return false
        }
    }
}

public extension NSManagedObjectContext {

    /**
     With a valid URL representation of a Managed Object ID, returns the managed object.
    */
    func object(withID id: URL) -> NSManagedObject {
        return object(with: persistentStoreCoordinator!.managedObjectID(forURIRepresentation: id)!)
    }
}

public extension NSPersistentStoreCoordinator {

    /**
     Attempts to destory and then delete the store at the specified URL. If an error occurs, prints the error; does not rethrow.
     */
    func destroyAndDeleteStore(at url: URL) {
        do {
            try destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.removeItem(at: URL(fileURLWithPath: url.path.appending("-shm")))
            try FileManager.default.removeItem(at: URL(fileURLWithPath: url.path.appending("-wal")))
        } catch {
            os_log("Failed to destroy or delete persistent store at %{public}s: %{public}s", type: .error, url.path, error.localizedDescription)
        }
    }
}

public extension NSEntityMigrationPolicy {

    func copyValue(oldObject: NSManagedObject, newObject: NSManagedObject, key: String) {
        newObject.setValue(oldObject.value(forKey: key), forKey: key)
    }

    func copyValues(oldObject: NSManagedObject, newObject: NSManagedObject, keys: String...) {
        for key in keys {
            copyValue(oldObject: oldObject, newObject: newObject, key: key)
        }
    }
}
