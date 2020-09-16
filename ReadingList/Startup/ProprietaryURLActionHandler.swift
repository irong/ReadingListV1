import Foundation
import UIKit

struct ProprietaryURLActionHandler {
    var window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func handle(_ action: ProprietaryURLAction) -> Bool {
        switch action {
        case .viewBook(id: let id):
            if let book = getBookFromIdentifier(id) {
                showBook(book)
                return true
            } else {
                return false
            }
        }
    }

    func getBookFromIdentifier(_ identifier: BookIdentifier) -> Book? {
        switch identifier {
        case .googleBooksId(let googleBooksId):
            return Book.get(fromContext: PersistentStoreManager.container.viewContext, googleBooksId: googleBooksId)
        case .isbn(let isbn):
            return Book.get(fromContext: PersistentStoreManager.container.viewContext, isbn: isbn)
        case .manualId(let manualId):
            return Book.get(fromContext: PersistentStoreManager.container.viewContext, manualBookId: manualId)
        }
    }

    func showBook(_ book: Book) {
        guard let tabBarController = window.rootViewController as? TabBarController else {
            assertionFailure()
            return
        }
        tabBarController.simulateBookSelection(book, allowTableObscuring: true)
    }
}
