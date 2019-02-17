import Foundation
import StoreKit
import Firebase

class UserEngagement {

    // Note: TestFlight users are automatically enrolled in analytics and crash reporting. This should be reflected
    // on the corresponding Settings page.
    static var sendAnalytics: Bool {
        #if DEBUG
        return false
        #else
        return BuildInfo.appConfiguration == .testFlight || UserDefaults.standard[.sendAnalytics]
        #endif
    }

    static var sendCrashReports: Bool {
        #if DEBUG
        return false
        #else
        return BuildInfo.appConfiguration == .testFlight || UserDefaults.standard[.sendCrashReports]
        #endif
    }

    static func initialiseUserAnalytics() {
        #if RELEASE
            if sendAnalytics { FirebaseApp.configure() }
            if sendCrashReports { Fabric.with([Crashlytics.self]) }
        #endif
    }

    static func onReviewTrigger() {
        UserDefaults.standard[.userEngagementCount] += 1
        if shouldTryRequestReview() {
            SKStoreReviewController.requestReview()
        }
    }

    static func onAppOpen() {
        UserDefaults.standard[.appStartupCount] += 1
    }

    enum Event: String {
        // Add books
        case searchOnline = "Search_Online"
        case scanBarcode = "Scan_Barcode"
        case searchOnlineMultiple = "Search_Online_Multiple"
        case addManualBook = "Add_Manual_Book"

        // Data
        case csvImport = "CSV_Import"
        case csvExport = "CSV_Export"
        case deleteAllData = "Delete_All_Data"

        // Modify books
        case transitionReadState = "Transition_Read_State"
        case bulkEditReadState = "Bulk_Edit_Read_State"
        case deleteBook = "Delete_Book"
        case bulkDeleteBook = "Bulk_Delete_Book"
        case editBook = "Edit_Book"
        case editReadState = "Edit_Read_State"

        // Lists
        case createList = "Create_List"
        case addBookToList = "Add_Book_To_List"
        case bulkAddBookToList = "Bulk_Add_Book_To_List"
        case removeBookFromList = "Remove_Book_From_List"
        case reorederList = "Reorder_List"
        case deleteList = "Delete_List"
        case setListOrder = "Set_List_Order"
        case renameList = "Rename_List"

        // Quick actions
        case searchOnlineQuickAction = "Quick_Action_Search_Online"
        case scanBarcodeQuickAction = "Quick_Action_Scan_Barcode"

        // Settings changes
        case disableAnalytics = "Disable_Analytics"
        case enableAnalytics = "Enable_Analytics"
        case disableCrashReports = "Disable_Crash_Reports"
        case enableCrashReports = "Enable_Crash_Reports"
        case changeTheme = "Change_Theme"
        case changeSortOrder = "Change_Sort"

        // Other
        case viewOnAmazon = "View_On_Amazon"
        case openCsvInApp = "Open_CSV_In_App"
    }

    static func logEvent(_ event: Event) {
        guard sendAnalytics else { return }
        Analytics.logEvent(event.rawValue, parameters: nil)
    }

    static func logError(_ error: Error) {
        guard sendCrashReports else { return }
        Crashlytics.sharedInstance().recordError(error)
    }

    private static func shouldTryRequestReview() -> Bool {
        let appStartCountMinRequirement = 3
        let userEngagementModulo = 10

        let appStartCount = UserDefaults.standard[.appStartupCount]
        let userEngagementCount = UserDefaults.standard[.userEngagementCount]

        return appStartCount >= appStartCountMinRequirement && userEngagementCount % userEngagementModulo == 0
    }
}
