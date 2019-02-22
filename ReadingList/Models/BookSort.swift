import Foundation
import ReadingList_Foundation

@objc public enum BookSort: Int16, CaseIterable, CustomStringConvertible, UserSettingType {
    case custom = 1
    case startDate = 2
    case finishDate = 3
    case title = 4
    case author = 5
    case listCustom = 6

    public var description: String {
        switch self {
        case .custom, .listCustom: return "Custom"
        case .startDate: return "Start Date"
        case .finishDate: return "Finish Date"
        case .title: return "Title"
        case .author: return "Author"
        }
    }

    static var listSorts = [BookSort.listCustom, .title, .author, .startDate, .finishDate]

    static func bookSorts(forState state: BookReadState) -> [BookSort] {
        switch state {
        case .toRead: return [BookSort.custom, .title, .author]
        case .reading: return [BookSort.startDate, .title, .author]
        case .finished: return [BookSort.startDate, .finishDate, .title, .author]
        }
    }

    var sortDescriptors: [NSSortDescriptor] {
        switch self {
        case .title: return [NSSortDescriptor(\Book.title)]
        case .author: return [NSSortDescriptor(\Book.authorSort),
                              NSSortDescriptor(\Book.title)]
        case .startDate: return [NSSortDescriptor(\Book.startedReading, ascending: false),
                                 NSSortDescriptor(\Book.title)]
        case .finishDate: return [NSSortDescriptor(\Book.finishedReading, ascending: false),
                                  NSSortDescriptor(\Book.startedReading, ascending: false),
                                  NSSortDescriptor(\Book.title)]
        case .custom: return [NSSortDescriptor(Book.Key.sort.rawValue),
                              NSSortDescriptor(\Book.googleBooksId),
                              NSSortDescriptor(\Book.manualBookId)]
        case .listCustom: return [NSSortDescriptor(\Book.lists)]
        }
    }
}
