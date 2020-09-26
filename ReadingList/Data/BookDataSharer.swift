import Foundation
import CoreData
import WidgetKit
import os.log

@available(iOS 14.0, *)
class BookDataSharer {
    private init() {}

    static var instance = BookDataSharer()
    var persistentContainer: NSPersistentContainer!

    func inititialise(persistentContainer: NSPersistentContainer) {
        self.persistentContainer = persistentContainer
        NotificationCenter.default.addObserver(self, selector: #selector(handleChanges), name: .NSManagedObjectContextDidSave, object: persistentContainer.viewContext)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChanges), name: .NSManagedObjectContextDidMergeChangesObjectIDs, object: persistentContainer.viewContext)
        handleChanges(forceUpdate: false)
    }

    private let bookRetrievalCount = 8

    @objc func handleChanges(forceUpdate: Bool = false) {
        let background = persistentContainer.newBackgroundContext()
        background.perform { [unowned self] in
            let readingFetchRequest = fetchRequest(itemLimit: bookRetrievalCount, readState: .reading)
            var books = try! background.fetch(readingFetchRequest)

            if books.count < bookRetrievalCount {
                let toReadFetchRequest = fetchRequest(itemLimit: bookRetrievalCount - books.count, readState: .toRead)
                books.append(contentsOf: try! background.fetch(toReadFetchRequest))
            }

            let sharedData = books.map(\.sharedData)
            if forceUpdate || sharedData != SharedBookData.sharedBooks {
                os_log("Updating and reloading widget timelines", type: .default)
                DispatchQueue.main.async {
                    SharedBookData.sharedBooks = sharedData
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    private func fetchRequest(itemLimit: Int, readState: BookReadState) -> NSFetchRequest<Book> {
        let fetchRequest = NSFetchRequest<Book>()
        fetchRequest.entity = Book.entity()
        fetchRequest.fetchLimit = itemLimit
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "%K == %ld", #keyPath(Book.readState), readState.rawValue)
        fetchRequest.sortDescriptors = BookSort.byReadState[readState]!.bookSortDescriptors
        return fetchRequest
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
        SharedBookData(title: title, authorDisplay: authors.fullNames, identifier: identifier, coverImage: coverImage, percentageComplete: Int(currentPercentage), currentlyReading: readState == .reading)
    }
}
