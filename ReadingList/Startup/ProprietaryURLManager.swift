import Foundation
import UIKit
import os.log

enum BookIdentifier: Equatable {
    case googleBooksId(_ id: String)
    case manualId(_ id: String)
    case isbn(_ isbn: String)
}

enum ProprietaryURLAction: Equatable {
    case viewBook(id: BookIdentifier)
}

fileprivate extension ProprietaryURLAction {
    var host: URLHost {
        switch self {
        case .viewBook(id: _): return .book
        }
    }

    var path: URLPath {
        switch self {
        case .viewBook(id: _): return .view
        }
    }
}

fileprivate extension BookIdentifier {
    var urlQuery: [URLQueryItem] {
        switch self {
        case .googleBooksId(let googleBooksId): return [URLQueryItem(name: URLQueryItemKey.googleBooksId.rawValue, value: googleBooksId)]
        case .manualId(let manualId): return [URLQueryItem(name: URLQueryItemKey.manualBookId.rawValue, value: manualId)]
        case .isbn(let isbn): return [URLQueryItem(name: URLQueryItemKey.isbn.rawValue, value: isbn)]
        }
    }
}

private enum URLQueryItemKey: String {
    case googleBooksId = "gbid"
    case manualBookId = "mid"
    case isbn = "isbn"
}

private enum URLHost: String {
    case book = "book" //swiftlint:disable:this redundant_string_enum_value
}

private enum URLPath: String {
    case view = "/view"
}

/// Handles app launch with a URL argument where the URL has scheme `readinglist://`
struct ProprietaryURLManager {
    static let scheme = "readinglist"

    func getURL(from action: ProprietaryURLAction) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = action.host.rawValue
        components.path = action.path.rawValue
        switch action {
        case .viewBook(let bookIdentifier):
            components.queryItems = bookIdentifier.urlQuery
        }

        guard let url = components.url else { preconditionFailure() }
        return url
    }

    func getAction(from url: URL) -> ProprietaryURLAction? {
        os_log("Handling URL: %{public}s", type: .default, url.absoluteString)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            os_log("Invalid URL", type: .error)
            return nil
        }
        guard let urlHost = components.host, let host = URLHost(rawValue: urlHost) else {
            os_log("Unexpected URL Host", type: .error)
            return nil
        }

        // The "host" is the first part of the URL, which we use to identify the kind of resource we are accessing.
        switch host {
        case .book:
            return getBookAction(path: components.path, queryItems: components.queryItems)
        }
    }

    private func getBookAction(path urlPath: String, queryItems: [URLQueryItem]?) -> ProprietaryURLAction? {
        guard let path = URLPath(rawValue: urlPath) else {
            os_log("Unexpected URL Path", type: .error)
            return nil
        }
        switch path {
        case .view:
            guard let bookIdentifier = getBookIdentifier(from: queryItems) else { return nil }
            return .viewBook(id: bookIdentifier)
        }
    }

    private func getBookIdentifier(from queryItems: [URLQueryItem]?) -> BookIdentifier? {
        guard let queryItems = queryItems else { return nil }
        if let googleBooksId = queryItems.first(where: { $0.name == URLQueryItemKey.googleBooksId.rawValue })?.value {
            return .googleBooksId(googleBooksId)
        } else if let isbn = queryItems.first(where: { $0.name == URLQueryItemKey.isbn.rawValue })?.value {
            return .isbn(isbn)
        } else if let manualId = queryItems.first(where: { $0.name == URLQueryItemKey.manualBookId.rawValue })?.value {
            return .manualId(manualId)
        } else {
            return nil
        }
    }
}
