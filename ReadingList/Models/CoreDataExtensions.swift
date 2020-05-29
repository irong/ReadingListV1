import Foundation
import CoreData

extension NSManagedObjectContext {

    /**
     Creates a child managed object context, and adds an observer to the child context's save event in order to trigger a merge and save
     */
    func childContext(concurrencyType: NSManagedObjectContextConcurrencyType = .mainQueueConcurrencyType, autoMerge: Bool = true) -> NSManagedObjectContext {
        let childContext = NSManagedObjectContext(concurrencyType: concurrencyType)
        childContext.parent = self
        childContext.automaticallyMergesChangesFromParent = autoMerge

        NotificationCenter.default.addObserver(self, selector: #selector(mergeAndSave(fromChildContextDidSave:)), name: .NSManagedObjectContextDidSave, object: childContext)

        return childContext
    }

    /**
     Tries to save the managed object context and logs an event and raises a fatal error if failure occurs.
     */
    func saveAndLogIfErrored() {
        do {
            try self.save()
        } catch let error as NSError {
            UserEngagement.logError(error)
            preconditionFailure(error.localizedDescription)
        }
    }

    /**
     Calls `obtainPermanentIDs(for:)`; if any error occured, the error is logged and a precondition failure is thrown.
     */
    func obtainPermanentIDsAndLogIfErrored(for objects: [NSManagedObject]) {
        do {
            try self.obtainPermanentIDs(for: objects)
        } catch let error as NSError {
            UserEngagement.logError(error)
            preconditionFailure(error.localizedDescription)
        }
    }

    @objc private func mergeAndSave(fromChildContextDidSave notification: Notification) {
        self.mergeChanges(fromContextDidSave: notification)
        self.saveAndLogIfErrored()
    }

    /**
     Saves if changes are present in the context.
     */
    @discardableResult func saveIfChanged() -> Bool {
        guard hasChanges else { return false }
        self.saveAndLogIfErrored()
        return true
    }

    func performAndSave(block: @escaping () -> Void) {
        perform { [unowned self] in
            block()
            self.saveAndLogIfErrored()
        }
    }
}

extension NSManagedObject {
    func deleteAndSave() {
        delete()
        managedObjectContext!.saveAndLogIfErrored()
    }
}
