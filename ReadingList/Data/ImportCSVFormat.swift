import Foundation

enum ImportCSVFormat: Int, Codable, CaseIterable {
    case readingList = 0
    case goodreads = 1
}

extension ImportCSVFormat: CustomStringConvertible {
    var description: String {
        switch self {
        case .readingList:
            return "Reading List"
        case .goodreads:
            return "Goodreads"
        }
    }
}

extension ImportCSVFormat {
    var requiredHeaders: [String] {
        switch self {
        case .readingList:
            return BookCSVColumn.allCases.filter(\.mandatoryForImport).map(\.header)
        case .goodreads:
            return ["Title", "Author l-f"]
        }
    }
}
