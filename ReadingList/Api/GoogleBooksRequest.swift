import Foundation
import ReadingList_Foundation

enum GoogleBooksRequest {

    case searchText(String, LanguageIso639_1?)
    case searchIsbn(String)
    case fetch(String)
    case coverImage(String, CoverType)
    case webpage(String)

    enum CoverType: Int {
        case thumbnail = 1
        case small = 2
    }

    // The base URL for GoogleBooks API v1 requests
    private static let apiBaseUrl = URL(string: "https://www.googleapis.com/")!
    private static let googleBooksHost = URL(string: "https://books.google.com/")!
    private static let searchResultFields = "items(id,volumeInfo(title,authors,industryIdentifiers,categories,imageLinks/thumbnail))"

    var baseUrl: URL {
        switch self {
        case .coverImage, .webpage:
            return GoogleBooksRequest.googleBooksHost
        default:
            return GoogleBooksRequest.apiBaseUrl
        }
    }

    var path: String {
        switch self {
        case .searchIsbn, .searchText:
            return "books/v1/volumes"
        case let .fetch(id):
            return "books/v1/volumes/\(id)"
        case .coverImage:
            return "books/content"
        case .webpage:
            return "books"
        }
    }

    var queryString: String? {
        switch self {
        case let .searchText(searchString, languageRestriction):
            let encodedQuery = searchString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
            let langQuery: String
            if let languageCode = languageRestriction {
                langQuery = "&langRestrict=\(languageCode.rawValue)"
            } else {
                langQuery = ""
            }
            return "q=\(encodedQuery)&maxResults=40&fields=\(GoogleBooksRequest.searchResultFields)\(langQuery)"
        case let .searchIsbn(isbn):
            return "q=isbn:\(isbn)&maxResults=40&fields=\(GoogleBooksRequest.searchResultFields)"
        case .fetch:
            return nil
        case let .coverImage(googleBooksId, coverType):
            return "id=\(googleBooksId)&printsec=frontcover&img=1&zoom=\(coverType.rawValue)"
        case let .webpage(googleBooksId):
            return "id=\(googleBooksId)"
        }
    }

    var pathAndQuery: String {
        if let queryString = queryString {
            return "\(path)?\(queryString)"
        } else {
            return path
        }
    }

    var url: URL {
        let fullUrl = URL(string: pathAndQuery, relativeTo: baseUrl)!
        #if DEBUG
        if CommandLine.arguments.contains("--UITests_MockHttpCalls") {
            
            let encodedUrl = fullUrl.absoluteString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.intersection(.urlHostAllowed).intersection(.urlQueryAllowed))!
            return URL(string: "http://localhost:8080/?url=\(encodedUrl)")!
        }
        #endif
        return fullUrl
    }
}
