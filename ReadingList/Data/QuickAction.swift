import Foundation
import UIKit

enum QuickAction: String {
    case scanBarcode = "com.andrewbennet.books.ScanBarcode"
    case searchOnline = "com.andrewbennet.books.SearchBooks"

    func perform(from root: TabBarController) {
        // All quick actions are presented from the To Read tab
        root.currentTab = .toRead

        // Dismiss any modal views before presenting
        let navController = root.selectedSplitViewController?.primaryNavigationController
        navController?.dismissAndPopToRoot()

        let viewController: UIViewController
        switch self {
        case .scanBarcode:
            UserEngagement.logEvent(.scanBarcodeQuickAction)
            viewController = UIStoryboard.ScanBarcode.rootAsFormSheet()
        case .searchOnline:
            UserEngagement.logEvent(.searchOnlineQuickAction)
            viewController = UIStoryboard.SearchOnline.rootAsFormSheet()
        }

        navController?.viewControllers.first?.present(viewController, animated: true, completion: nil)
    }
}
