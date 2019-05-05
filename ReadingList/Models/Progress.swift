import Foundation

enum Progress: Equatable {
    case percentage(Int32?)
    case page(Int32?)
}

enum ProgressType: Equatable, CustomStringConvertible {
    case page
    case percentage

    var description: String {
        switch self {
        case .page: return "Page"
        case .percentage: return "Percentage"
        }
    }
}
