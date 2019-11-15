import Foundation
import SwiftyJSON
import Promises
import ReadingList_Foundation
import os.log

class GoogleBooks {

    /**
     Searches on Google Books for the given search string
     */
    static func search(_ text: String) -> Promise<[SearchResult]> {
        os_log("Searching for Google Books with query", type: .debug)
        let languageRestriction = UserDefaults.standard[.searchLanguageRestriction]
        guard let url = GoogleBooksRequest.searchText(text, languageRestriction).url else {
            return Promise<[SearchResult]>(GoogleError.invalidUrl)
        }
        return URLSession.shared.json(url: url)
            .then(GoogleBooksParser.assertNoError)
            .then(GoogleBooksParser.parseSearchResults)
    }

    /**
     Searches on Google Books for the given ISBN
     */
    static func fetch(isbn: String) -> Promise<FetchResult> {
        os_log("Searching for Google Book with ISBN %{public}s", type: .debug, isbn)
        guard let url = GoogleBooksRequest.searchIsbn(isbn).url else {
            return Promise<FetchResult>(GoogleError.invalidUrl)
        }
        return URLSession.shared.json(url: url)
            .then(GoogleBooksParser.parseSearchResults)
            .then {
                guard let id = $0.first?.id else { throw GoogleError.noResult }
                return fetch(googleBooksId: id)
            }
    }

    /**
     Fetches the specified book from Google Books. Performs a supplementary request for the
     book's cover image data if necessary.
     */
    static func fetch(googleBooksId: String) -> Promise<FetchResult> {
        return fetch(googleBooksId: googleBooksId, existingSearchResult: nil)
    }

    /**
     Fetches the book identified by a search result from Google Books. If the fetch results are not sufficient
     to create a Book object (sometimes fetch results miss data which is present in a search result), an attempt
     is made to "mix" the data from the search and fetch results. Performs a supplementary request for the
     book's cover image data if necessary.
     */
    static func fetch(searchResult: SearchResult) -> Promise<FetchResult> {
        return fetch(googleBooksId: searchResult.id, existingSearchResult: searchResult)
    }

    /**
     Fetches the specified book from Google Books. If the results are not sufficient to create a Book object,
     and a search result was supplied, an attempt is made to "mix" the data from the search and fetch results.
     Performs a supplementary request for the book's cover image data if necessary.
     */
    private static func fetch(googleBooksId: String, existingSearchResult: SearchResult?) -> Promise<FetchResult> {
        os_log("Fetching Google Book with ID %{public}s", type: .debug, googleBooksId)
        guard let url = GoogleBooksRequest.fetch(googleBooksId).url else {
            return Promise<FetchResult>(GoogleError.invalidUrl)
        }
        let fetchPromise = URLSession.shared.json(url: url)
            .then { json -> FetchResult in
                if let fetchResult = GoogleBooksParser.parseFetchResults(json) {
                    return fetchResult
                }
                if let existingSearchResult = existingSearchResult,
                    let fetchResult = GoogleBooksParser.parseFetchResults(json, existingSearchResult: existingSearchResult) {
                    return fetchResult
                }
                throw GoogleError.missingEssentialData
            }

        let coverPromise = fetchPromise.then { getCover(googleBooksId: $0.id) }

        return any(fetchPromise, coverPromise).then { fetch, cover -> FetchResult in
            switch fetch {
            case let .value(fetchResultValue):
                if case let .value(coverDataValue) = cover {
                    fetchResultValue.coverImage = coverDataValue
                }
                return fetchResultValue
            case let .error(fetchResultError):
                throw fetchResultError
            }
        }
    }

    /**
     Gets the cover image data for the book corresponding to the Google Books ID (if exists).
     */
    static func getCover(googleBooksId: String) -> Promise<Data> {
        guard let url = GoogleBooksRequest.coverImage(googleBooksId, .thumbnail).url else {
            return Promise<Data>(GoogleError.invalidUrl)
        }
        return URLSession.shared.data(url: url)
    }
}

class GoogleBooksParser {

    static func parseError(json: JSON) -> GoogleError? {
        if let code = json["error", "code"].int, let message = json["error", "message"].string {
            return GoogleError.specifiedError(code: code, message: message)
        }
        return nil
    }

    static func assertNoError(json: JSON) throws -> JSON {
        if let error = GoogleBooksParser.parseError(json: json) {
            throw error
        } else {
            return json
        }
    }

    static func parseSearchResults(_ searchResults: JSON) -> [SearchResult] {
        return searchResults["items"].map { $0.1 }.reduce([SearchResult]()) { result, element in
            guard let item = GoogleBooksParser.parseItem(element) else { return result }
            guard !result.contains(where: { $0.id == item.id }) else { return result }
            return result + [item]
        }
    }

    static func parseItem(_ item: JSON) -> SearchResult? {
        guard let id = item["id"].string, !id.isEmptyOrWhitespace,
            let title = item["volumeInfo", "title"].string, !title.isEmptyOrWhitespace,
            let authorsJson = item["volumeInfo", "authors"].array, !authorsJson.isEmpty else { return nil }
        let authors = authorsJson.compactMap { json -> String? in
            guard let authorString = json.rawString(), !authorString.isEmptyOrWhitespace else { return nil }
            return authorString
        }
        guard !authors.isEmpty else { return nil }

        let result = SearchResult(id: id, title: title, authors: authors)
        result.subtitle = item["volumeInfo", "subtitle"].string

        // Convert the thumbnail URL to HTTPS
        if let thumbnailUrlString = item["volumeInfo", "imageLinks", "thumbnail"].string,
            let thumbnailUrl = URL(string: thumbnailUrlString) {
            var urlComponents = URLComponents(url: thumbnailUrl, resolvingAgainstBaseURL: false)!
            urlComponents.scheme = "https"
            result.thumbnailCoverUrl = urlComponents.url
        }
        result.isbn13 = item["volumeInfo", "industryIdentifiers"].array?.first {
            $0["type"].stringValue == "ISBN_13"
        }?["identifier"].stringValue

        return result
    }

    static func parseFetchResults(_ fetchResult: JSON, existingSearchResult: SearchResult? = nil) -> FetchResult? {

        // Defer to the common search parsing initially, or use the provided search result
        guard let searchResult = existingSearchResult ?? GoogleBooksParser.parseItem(fetchResult) else { return nil }

        let result = FetchResult(fromSearchResult: searchResult)
        result.pageCount = fetchResult["volumeInfo", "pageCount"].int32
        if let code = fetchResult["volumeInfo"]["language"].string, let language = LanguageIso639_1(rawValue: code) {
            result.language = language
        }

        // Note: "Published Date" refers to *this* edition; there doesn't seem to be a way to get the first publication date
        result.publisher = fetchResult["volumeInfo", "publisher"].string

        result.hasSmallImage = fetchResult["volumeInfo", "imageLinks", "small"].string != nil
        result.hasThumbnailImage = fetchResult["volumeInfo", "imageLinks", "thumbnail"].string != nil

        // This string may contain some HTML. We want to remove them, but first we might as well replace the "<br>"s with '\n's
        // and the "<p>"s with "\n\n".
        var description = fetchResult["volumeInfo", "description"].string

        description = description?.components(separatedBy: "<br>")
            .map { $0.trimming() }
            .joined(separator: "\n")

        description = description?.components(separatedBy: "<p>")
            .flatMap { $0.components(separatedBy: "</p>") }
            .compactMap { $0.trimming().nilIfWhitespace() }
            .joined(separator: "\n\n")

        description = description?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.description = description

        // Try to get the categories
        if let subjects = fetchResult["volumeInfo", "categories"].array {
            result.subjects = subjects.flatMap {
                $0.stringValue.components(separatedBy: "/").map { $0.trimming() }
            }.filter { $0 != "General" }.distinct()
        }

        return result
    }
}

class SearchResult {
    let id: String
    var title: String
    var subtitle: String?
    var authors: [Author]
    var isbn13: String?
    var thumbnailCoverUrl: URL?

    init(id: String, title: String, authors: [String]) {
        self.id = id
        self.title = title
        self.authors = authors.map {
            if let range = $0.range(of: " ", options: .backwards) {
                let firstNames = $0[..<range.upperBound].trimming()
                let lastName = $0[range.lowerBound...].trimming()
                return Author(lastName: lastName, firstNames: firstNames)
            } else {
                return Author(lastName: $0, firstNames: nil)
            }
        }
    }
}

class FetchResult {
    let id: String
    var title: String
    var subtitle: String?
    var authors = [Author]()
    var isbn13: ISBN13?
    var description: String?
    var publisher: String?
    var subjects = [String]()
    var language: LanguageIso639_1?
    var publishedDate: Date?
    var pageCount: Int32?
    var hasThumbnailImage: Bool = false
    var hasSmallImage: Bool = false

    var coverImage: Data?

    init(fromSearchResult searchResult: SearchResult) {
        id = searchResult.id
        title = searchResult.title
        subtitle = searchResult.subtitle
        authors = searchResult.authors
        isbn13 = ISBN13(searchResult.isbn13)
    }
}

enum GoogleError: Error {
    case noResult
    case missingEssentialData
    case invalidUrl
    case specifiedError(code: Int, message: String)
}
