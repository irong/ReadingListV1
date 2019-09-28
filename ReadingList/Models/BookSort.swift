import Foundation
import ReadingList_Foundation

@objc public enum BookSort: Int16, CaseIterable, CustomStringConvertible, UserSettingType {
    // The order of this enum determines the order that the settings are shown in menus, via the allCases property
    case custom = 1
    case listCustom = 6
    case startDate = 2
    case finishDate = 3
    case title = 4
    case subtitle = 7
    case author = 5
    case progress = 8
    case rating = 9

    public var description: String {
        switch self {
        case .custom, .listCustom: return "Custom"
        case .startDate: return "Start Date"
        case .finishDate: return "Finish Date"
        case .title: return "Title"
        case .author: return "Author"
        case .subtitle: return "Subtitle"
        case .progress: return "Progress"
        case .rating: return "Rating"
        }
    }

    public var supportsListSorting: Bool {
        switch self {
        case .listCustom, .title, .author, .startDate, .finishDate, .subtitle, .rating:
            return true
        case .custom, .progress:
            return false
        }
    }

    func supports(_ state: BookReadState) -> Bool {
        switch self {
        case .custom, .title, .subtitle, .author: return true
        case .listCustom, .rating: return false
        case .startDate: return state == .reading || state == .finished
        case .finishDate: return state == .finished
        case .progress: return state == .reading
        }
    }

    var sortDescriptors: [NSSortDescriptor] {
        switch self {
        case .title: return [NSSortDescriptor(\Book.title), NSSortDescriptor(\Book.subtitle)]
        case .subtitle: return [NSSortDescriptor(\Book.hasSubtitle, ascending: false), NSSortDescriptor(\Book.subtitle), NSSortDescriptor(\Book.title)]
        case .author: return [NSSortDescriptor(\Book.authorSort),
                              NSSortDescriptor(\Book.title)]
        case .startDate: return [NSSortDescriptor(\Book.startedReading, ascending: false),
                                 NSSortDescriptor(\Book.title)]
        case .finishDate: return [NSSortDescriptor(\Book.finishedReading, ascending: false),
                                  NSSortDescriptor(\Book.startedReading, ascending: false),
                                  NSSortDescriptor(\Book.title)]
        case .custom: return [NSSortDescriptor(\Book.sort),
                              NSSortDescriptor(\Book.googleBooksId),
                              NSSortDescriptor(\Book.manualBookId)]
        case .listCustom: return [NSSortDescriptor(\Book.lists)]
        case .progress: return [NSSortDescriptor(Book.Key.currentPercentage.rawValue)]
        case .rating: return [NSSortDescriptor(Book.Key.rating.rawValue, ascending: false)]
        }
    }
}
