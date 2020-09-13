import Foundation
import UIKit
import os.log

/// Handles app launch with a URL argument where the URL has scheme `readinglist://`
struct ProprietaryUrlHandler {
    var window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func handleUrl(_ url: URL) -> Bool {
        os_log("Handling URL: %{public}s", type: .default, url.absoluteString)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            os_log("Invalid URL", type: .error)
            return false
        }

        // The "host" is the first part of the URL, which we use to identify the kind of resource we are accessing.
        switch components.host {
        case "book":
            return handleBookUrl(path: components.path, queryItems: components.queryItems)
        default:
            os_log("Unexpected URL host", type: .error)
            return false
        }
    }

    private func handleBookUrl(path: String, queryItems: [URLQueryItem]?) -> Bool {
        switch path {
        case "/view":
            guard let queryItems = queryItems else { return false }
            return viewBook(queryItems: queryItems)
        default:
            os_log("Unexpected URL path", type: .error)
            return false
        }
    }

    private func viewBook(queryItems: [URLQueryItem]) -> Bool {
        let googleBooksId = queryItems.first { $0.name == "gbid" }?.value
        let isbn = queryItems.first { $0.name == "isbn" }?.value
        let manualId = queryItems.first { $0.name == "mid" }?.value

        if let book = Book.get(fromContext: PersistentStoreManager.container.viewContext, googleBooksId: googleBooksId, isbn: isbn, manualBookId: manualId) {
            showBook(book)
            return true
        } else {
            return false
        }
    }

    private func showBook(_ book: Book) {
        guard let tabBarController = window.rootViewController as? TabBarController else {
            assertionFailure()
            return
        }
        tabBarController.simulateBookSelection(book, allowTableObscuring: true)
    }
}
