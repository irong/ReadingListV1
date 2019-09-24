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

    public var description: String {
        switch self {
        case .custom, .listCustom: return "Custom"
        case .startDate: return "Start Date"
        case .finishDate: return "Finish Date"
        case .title: return "Title"
        case .author: return "Author"
        case .subtitle: return "Subtitle"
        }
    }

    public var supportsListSorting: Bool {
        switch self {
        case .listCustom, .title, .author, .startDate, .finishDate, .subtitle:
            return true
        case .custom:
            return false
        }
    }

    func supports(_ state: BookReadState) -> Bool {
        switch self {
        case .custom, .title, .subtitle, .author: return true
        case .listCustom: return false
        case .startDate: return state == .reading || state == .finished
        case .finishDate: return state == .finished
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
        }
    }
}
