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
        let backgroundContext = persistentContainer.newBackgroundContext()
        backgroundContext.perform { [unowned self] in
            let readingFetchRequest = fetchRequest(itemLimit: bookRetrievalCount, readState: .reading)
            var currentBooks = try! backgroundContext.fetch(readingFetchRequest)

            if currentBooks.count < bookRetrievalCount {
                let toReadFetchRequest = fetchRequest(itemLimit: bookRetrievalCount - currentBooks.count, readState: .toRead)
                currentBooks.append(contentsOf: try! backgroundContext.fetch(toReadFetchRequest))
            }

            let finishedBooksRequest = fetchRequest(itemLimit: bookRetrievalCount, readState: .finished, sortOrderOverride: .finishDate)
            let finishedBooks = try! backgroundContext.fetch(finishedBooksRequest)

            let currentBooksData = currentBooks.map(\.sharedData)
            let finishedBooksData = finishedBooks.map(\.sharedData)
            if forceUpdate {
                os_log("Updating and reloading all widget timelines", type: .default)
                DispatchQueue.main.async {
                    SharedBookData.currentBooks = currentBooksData
                    SharedBookData.finishedBooks = finishedBooksData
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } else {
                if currentBooksData != SharedBookData.currentBooks {
                    os_log("Updating and reloading Current Books widget timelines", type: .default)
                    DispatchQueue.main.async {
                        SharedBookData.currentBooks = currentBooksData
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.currentBooks)
                    }
                }
                if finishedBooksData != SharedBookData.finishedBooks {
                    os_log("Updating and reloading Finished Books widget timelines", type: .default)
                    DispatchQueue.main.async {
                        SharedBookData.finishedBooks = finishedBooksData
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.finishedBooks)
                    }
                }
            }
        }
    }

    private func fetchRequest(itemLimit: Int, readState: BookReadState, sortOrderOverride: BookSort? = nil) -> NSFetchRequest<Book> {
        let fetchRequest = NSFetchRequest<Book>()
        fetchRequest.entity = Book.entity()
        fetchRequest.fetchLimit = itemLimit
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "%K == %ld", #keyPath(Book.readState), readState.rawValue)
        if let sortOrderOverride = sortOrderOverride {
            fetchRequest.sortDescriptors = sortOrderOverride.bookSortDescriptors
        } else {
            fetchRequest.sortDescriptors = BookSort.byReadState[readState]!.bookSortDescriptors
        }
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
        SharedBookData(
            title: title,
            authorDisplay: authors.fullNames,
            identifier: identifier,
            coverImage: coverImage,
            percentageComplete: Int(currentPercentage),
            startDate: startedReading,
            finishDate: finishedReading
        )
    }
}
