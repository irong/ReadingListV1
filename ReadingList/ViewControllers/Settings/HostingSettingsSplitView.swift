import Foundation
import SwiftUI

enum SettingsSelection {
    case about
    case general
    case tip
    case sort
    case importExport
    case backup
}

class HostingSettingsSplitView: ObservableObject, HostingSplitView {
    @Published var isSplit = false
    @Published var selectedCell: SettingsSelection?
}
