import UIKit
import CoreSpotlight
import Eureka
import SwiftUI

final class TabBarController: UITabBarController {

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        initialise()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialise()
    }

    enum TabOption: Int, CaseIterable {
        case toRead = 0
        case finished = 1
        case organise = 2
        case settings = 3
        
        var title: String {
            switch self {
            case .toRead: return "To Read"
            case .finished: return "Finished"
            case .organise: return NSLocalizedString("OrganizeTabText", comment: "")
            case .settings: return "Settings"
            }
        }
        
        var icon: (default: UIImage, selected: UIImage) {
            switch self {
            case .toRead: return (#imageLiteral(resourceName: "courses"), #imageLiteral(resourceName: "courses-filled"))
            case .finished: return (#imageLiteral(resourceName: "to-do"), #imageLiteral(resourceName: "to-do-filled"))
            case .organise: return (#imageLiteral(resourceName: "organise"), #imageLiteral(resourceName: "organise-filled"))
            case .settings: return (#imageLiteral(resourceName: "settings"), #imageLiteral(resourceName: "settings-filled"))
            }
        }
    }

    func initialise() {
        viewControllers = getRootViewControllers()
        configureTabIcons()

        // Update the settings badge if we stop or start being able to run auto backup
        NotificationCenter.default.addObserver(self, selector: #selector(configureTabIcons), name: .autoBackupEnabledOrDisabled, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(configureTabIcons), name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
    }

    func getRootViewControllers() -> [UIViewController] {
        // The first two tabs of the tab bar controller are to the same storyboard. We cannot have different tab bar icons
        // if they are set up in storyboards, so we do them in code here, instead.
        let toRead = UIStoryboard.BookTable.instantiateRoot() as! UISplitViewController
        (toRead.primaryNavigationRoot as! BookTable).readStates = [.reading, .toRead]

        let finished = UIStoryboard.BookTable.instantiateRoot() as! UISplitViewController
        (finished.primaryNavigationRoot as! BookTable).readStates = [.finished]

        let settings = buildSettingsVC()
        return [toRead, finished, UIStoryboard.Organize.instantiateRoot(), settings]
    }

    var hostingSettingsSplitView: HostingSettingsSplitView?
    var settingsSplitViewObserver: Any?

    private func buildSettingsVC() -> SplitViewController {
        let settings = SplitViewController()
        let hostingSplitView = HostingSettingsSplitView()
        settings.hostingSplitView = hostingSplitView
        settings.viewControllers = [
            UIHostingController(rootView: Settings().environmentObject(hostingSplitView)).inNavigationController()
        ]

        let aboutVc = UIHostingController(rootView: About().environmentObject(hostingSplitView)).inNavigationController()
        settings.showDetailViewController(aboutVc, sender: self)
        hostingSplitView.isSplit = !settings.isCollapsed

        settingsSplitViewObserver = hostingSplitView.$selectedCell.sink { type in
            func hostingDetail<T>(_ view: T, title: String? = nil) -> UIViewController where T: View {
                let hostingController = UIHostingController(rootView: view.environmentObject(hostingSplitView))
                hostingController.navigationItem.title = title
                return hostingController.inNavigationController()
            }

            let destination: UIViewController
            switch type {
            case .about: destination = aboutVc
            case .appearance: destination = hostingDetail(Appearance(), title: "Appearance")
            case .appIcon: destination = hostingDetail(AppIcon(), title: "App Icon")
            case .general: destination = hostingDetail(General(), title: "General")
            case .tip: destination = hostingDetail(Tip(), title: "Tip")
            case .importExport: destination = UIStoryboard.ImportExport.instantiateRoot()
            case .backup: destination = UIStoryboard.Backup.instantiateRoot()
            case .privacy: destination = hostingDetail(Privacy())
            case .none: destination = UIViewController()
            }
            settings.showDetailViewController(destination, sender: settings)
        }
        self.hostingSettingsSplitView = hostingSplitView
        return settings
    }

    @objc func configureTabIcons() {
        guard let items = tabBar.items else { preconditionFailure("Missing tab bar items") }
        
        for (index, option) in TabOption.allCases.enumerated() {
            items[index].configure(
                tag: option.rawValue,
                title: option.title,
                image: option.icon.default,
                selectedImage: option.icon.selected
            )
        }
        
        // Update settings badge if auto backup is not available
        if AutoBackupManager.shared.cannotRunScheduledAutoBackups {
            items[TabOption.settings.rawValue].badgeValue = "1"
        } else {
            items[TabOption.settings.rawValue].badgeValue = nil
        }
    }

    var currentTab: TabOption {
        get { TabOption(rawValue: selectedIndex) ?? .toRead }
        set { selectedIndex = newValue.rawValue }
    }

    var selectedSplitViewController: UISplitViewController? {
        return selectedViewController as? UISplitViewController
    }

    var selectedBookTable: BookTable? {
        return selectedSplitViewController?.primaryNavigationController.viewControllers.first as? BookTable
    }

    func simulateBookSelection(_ book: Book, allowTableObscuring: Bool) {
        currentTab = book.readState == .finished ? .finished : .toRead
        
        // Handle view loading state
        if selectedBookTable?.viewIfLoaded == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      self.selectedBookTable?.viewIfLoaded != nil else { return }
                self.selectedBookTable?.simulateBookSelection(book.objectID, allowTableObscuring: allowTableObscuring)
            }
        } else {
            selectedBookTable?.simulateBookSelection(book.objectID, allowTableObscuring: allowTableObscuring)
        }
    }

    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        // Scroll to top of table if the selected tab is already selected
        guard let selectedSplitViewController = selectedSplitViewController, item.tag == selectedIndex else { return }

        if selectedSplitViewController.primaryNavigationController.viewControllers.count > 1 {
           selectedSplitViewController.primaryNavigationController.popToRootViewController(animated: true)
        } else if let topVc = selectedSplitViewController.primaryNavigationController.viewControllers.first,
            let topTable = (topVc as? UITableViewController)?.tableView ?? (topVc as? FormViewController)?.tableView,
            topTable.numberOfSections > 0 {
                topTable.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        }
    }

    func presentImportExportView(importUrl: URL?) {
        // First select the correct tab (Settings)
        currentTab = .settings
        guard let settingsSplitVC = selectedSplitViewController else { fatalError("Unexpected missing selected view controller") }

        // Dismiss any existing navigation stack (implementation depends on whether the views are split or not)
        settingsSplitVC.popSecondaryOrPrimaryToRoot(animated: false)

        // Select the Import Export row to ensure it is highlighted
        hostingSettingsSplitView?.selectedCell = .importExport

        // Instantiate the stack of view controllers leading up to the Import view controller
        guard let navigation = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "Navigation") as? UINavigationController else {
            fatalError("Missing Navigation view controller")
        }
        let navigationViewControllers: [UIViewController]
        let importExportVC = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "ImportExport")

        // Instantiate the Import view controller, if an Import url is provided
        if let importUrl = importUrl {
            guard let importVC = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "Import") as? Import else {
                fatalError("Missing Import view controller")
            }
            importVC.preProvidedImportFile = importUrl
            navigationViewControllers = [importExportVC, importVC]
        } else {
            navigationViewControllers = [importExportVC]
        }

        // Set the navigation controller's the array of view controllers
        navigation.setViewControllers(navigationViewControllers, animated: false)

        // Put them on the screen
        settingsSplitVC.showDetailViewController(navigation, sender: self)
    }

    func presentBackupView() {
        // First select the correct tab (Settings)
        currentTab = .settings
        guard let settingsSplitVC = selectedSplitViewController else { fatalError("Unexpected missing selected view controller") }

        // Dismiss any existing navigation stack (implementation depends on whether the views are split or not)
        settingsSplitVC.popSecondaryOrPrimaryToRoot(animated: false)

        // Select the Backup row to ensure it is highlighted
        hostingSettingsSplitView?.selectedCell = .backup

        // Instantiate the destination view controller
        guard let backupVC = UIStoryboard.Backup.instantiateViewController(withIdentifier: "Backup") as? Backup else {
            fatalError("Missing Backup view controller")
        }

        // Instantiate the navigation view controller leading up to the Backup view controller
        guard let navigation = UIStoryboard.Backup.instantiateViewController(withIdentifier: "Navigation") as? UINavigationController else {
            fatalError("Missing Navigation view controller")
        }
        navigation.setViewControllers([backupVC], animated: false)

        // Put them on the screen
        settingsSplitVC.showDetailViewController(navigation, sender: self)
    }
}
