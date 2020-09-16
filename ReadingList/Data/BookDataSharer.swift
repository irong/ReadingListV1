import Foundation
import CoreData
import WidgetKit

@available(iOS 14.0, *)
class BookDataSharer {
    private init() {}
    
    static var instance = BookDataSharer()
    var persistentContainer: NSPersistentContainer!
    
    func inititialise(persistentContainer: NSPersistentContainer) {
        self.persistentContainer = persistentContainer
        // TODO: Or should this be a merge notificaiton or something?
        NotificationCenter.default.addObserver(self, selector: #selector(handleSave), name: .NSManagedObjectContextDidSave, object: persistentContainer.viewContext)
        handleSave()
    }
    
    @objc func handleSave() {
        let background = persistentContainer.newBackgroundContext()
        background.perform {
            let fetchRequest = NSFetchRequest<Book>()
            fetchRequest.entity = Book.entity()
            fetchRequest.fetchLimit = 4
            fetchRequest.predicate = NSPredicate(format: "%K == %ld", #keyPath(Book.readState), BookReadState.reading.rawValue)
            let books = try! background.fetch(fetchRequest)
            SharedBookData.sharedBooks = books.map(\.sharedData)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

fileprivate extension Book {
    var identifier: BookIdentifier {
        if let googleBooksId = googleBooksId {
            return .googleBooksId(googleBooksId)
        } else if let manualBookId = manualBookId {
            return .manualId(manualBookId)
        } else {
            preconditionFailure()
        }
    }
    
    var sharedData: SharedBookData {
        SharedBookData(title: title, authorDisplay: authors.fullNames, identifier: identifier, coverImage: coverImage)
    }
}
