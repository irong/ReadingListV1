import Foundation
import SwiftyStoreKit
import SVProgressHUD
import os.log
import CoreData
import ReadingList_Foundation

class LaunchManager {

    var window: UIWindow!
    var storeMigrationFailed = false
    var isFirstLaunch = false

    /**
     Performs any required initialisation immediately post after the app has launched.
     This must be called prior to any other initialisation actions.
    */
    func initialise(window: UIWindow) {
        self.window = window

        isFirstLaunch = AppLaunchHistory.appOpenedCount == 0
        #if DEBUG
        Debug.initialiseSettings()
        #endif
        UserEngagement.initialiseUserAnalytics()
        SVProgressHUD.setDefaults()
        SwiftyStoreKit.completeTransactions()
    }

    func handleApplicationDidBecomeActive() {
        AppLaunchHistory.appOpenedCount += 1

        if storeMigrationFailed {
            presentIncompatibleDataAlert()
        }
    }

    func extractRelevantLaunchOptions(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> LaunchOptions {
        let quickAction: QuickAction?
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            quickAction = QuickAction(rawValue: shortcut.type)
        } else {
            quickAction = nil
        }

        let csvFileUrl: URL?
        if let url = launchOptions?[.url] as? URL {
            csvFileUrl = url.isFileURL && url.pathExtension == "csv" ? url : nil
        } else {
            csvFileUrl = nil
        }

        return LaunchOptions(url: csvFileUrl, quickAction: quickAction)
    }

    /**
     Initialises the persistent store on a background thread. If successfully completed, the main thread
     will instantiate the root view controller, perform some other app-startup work. If the persistent store
     fails to initialise, then an error alert is presented to the user.
     */
    func initialisePersistentStore(_ options: LaunchOptions? = nil) {
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try PersistentStoreManager.initalisePersistentStore {
                    os_log("Persistent store loaded", type: .info)
                    DispatchQueue.main.async {
                        self.initialiseAfterPersistentStoreLoad()
                        if let options = options {
                            self.handleLaunchOptions(options)
                        }
                    }
                }
            } catch MigrationError.incompatibleStore {
                DispatchQueue.main.async {
                    self.storeMigrationFailed = true
                    self.presentIncompatibleDataAlert()
                }
            } catch {
                UserEngagement.logError(error)
                fatalError(error.localizedDescription)
            }
        }
    }

    private func handleLaunchOptions(_ options: LaunchOptions) {
        guard let tabBarController = window.rootViewController as? TabBarController else {
            assertionFailure()
            return
        }

        if let quickAction = options.quickAction {
            quickAction.perform(from: tabBarController)
        } else if let csvFileUrl = options.url {
            self.handleOpenUrl(csvFileUrl)
        }
    }

    /**
     Returns whether the provided URL could be handled.
    */
    @discardableResult func handleOpenUrl(_ url: URL) -> Bool {
        if url.isFileURL && url.pathExtension == "csv" {
            return openCsvFileInApp(url: url)
        } else if url.scheme == "readinglist" {
            os_log("Handling URL: %{public}s", type: .default, url.absoluteString)
            // The "host" is the first part of the URL, which we use to identify the kind of thing we are opening/doing.
            // "object" means show an object. Note: url.path starts with a "/" which we need to drop.
            if url.host == "object", let coreDataUrl = URL(string: "x-coredata://\(url.path.dropFirst())") {
                return showBook(withId: coreDataUrl)
            }
            return false
        } else {
            os_log("Unrecognised URL type; handling not possible: %{public}s", type: .error, url.absoluteString)
            return false
        }
    }

    private func showBook(withId coreDataId: URL) -> Bool {
        guard let tabBarController = window.rootViewController as? TabBarController else {
            assertionFailure()
            return false
        }
        guard let objectId = PersistentStoreManager.container.viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: coreDataId) else {
            return false
        }
        if let book = PersistentStoreManager.container.viewContext.object(with: objectId) as? Book {
            tabBarController.simulateBookSelection(book, allowTableObscuring: true)
            return true
        } else {
            return false
        }
    }

    private func openCsvFileInApp(url: URL) -> Bool {
        guard let tabBarController = window.rootViewController as? TabBarController else {
            assertionFailure()
            return false
        }
        UserEngagement.logEvent(.openCsvInApp)

        // First select the correct tab (Settings)
        tabBarController.selectedTab = .settings
        let settingsSplitVC = tabBarController.selectedSplitViewController!

        // Dismiss any existing navigation stack (implementation depends on whether the views are split or not)
        if let detailNav = settingsSplitVC.detailNavigationController {
            detailNav.popToRootViewController(animated: false)
        } else {
            settingsSplitVC.masterNavigationController.popToRootViewController(animated: false)
        }

        // Select the Import Export row to ensure it is highlighted
        guard let settingsVC = settingsSplitVC.masterNavigationController.viewControllers.first as? Settings else {
            assertionFailure()
            return false
        }
        settingsVC.tableView.selectRow(at: Settings.importExportIndexPath, animated: false, scrollPosition: .none)

        // Instantiate the destination view controller
        guard let importVC = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "Import") as? Import else {
            assertionFailure()
            return false
        }

        // Instantiate the stack of view controllers leading up to the Import view controller
        guard let navigation = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "Navigation") as? UINavigationController else {
            preconditionFailure()
        }
        navigation.setViewControllers([
            UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "ImportExport"),
            importVC
        ], animated: false)

        // Put them on the screen
        settingsSplitVC.showDetailViewController(navigation, sender: self)

        // Trigger the import dialog - wait to ensure the view controller is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            importVC.confirmImport(fromFile: url)
        }
        return true
    }

    func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let quickAction = QuickAction(rawValue: shortcutItem.type) else { return false }
        guard let tabBarController = window.rootViewController as? TabBarController else { return false }
        quickAction.perform(from: tabBarController)
        return true
    }

    private func initialiseAfterPersistentStoreLoad() {
        #if DEBUG
        Debug.initialiseData()
        #endif
        window.rootViewController = TabBarController()

        // Initialise app-level theme, and monitor the set theme, if < iOS 13
        if #available(iOS 13.0, *) { } else {
            initialiseTheme()
            NotificationCenter.default.addObserver(self, selector: #selector(self.initialiseTheme), name: .ThemeSettingChanged, object: nil)
        }

        if isFirstLaunch {
            let firstOpenScreen = FirstOpenScreenProvider().build()
            window.rootViewController!.present(firstOpenScreen, animated: true)
        } else if let lastLaunchedVersion = AppLaunchHistory.lastLaunchedVersion {
            if let changeList = ChangeListProvider().changeListController(after: lastLaunchedVersion) {
                window.rootViewController!.present(changeList, animated: true)
            }
        }

        AppLaunchHistory.lastLaunchedVersion = BuildInfo.thisBuild.version
        AppLaunchHistory.mostRecentWorkingVersionDescription = BuildInfo.thisBuild.fullDescription
    }

    @available(iOS, obsoleted: 13.0)
    @objc private func initialiseTheme() {
        if #available(iOS 13.0, *) { return }
        let theme = GeneralSettings.theme
        theme.configureForms()
        window.tintColor = theme.tint
    }

    private func presentIncompatibleDataAlert() {
        #if RELEASE
        // This is a common error during development, but shouldn't occur in production
        guard AppLaunchHistory.mostRecentWorkingVersionDescription != BuildInfo.thisBuild.fullDescription else {
            UserEngagement.logError(
                NSError(code: .invalidMigration,
                        userInfo: ["mostRecentWorkingVersion": AppLaunchHistory.mostRecentWorkingVersionDescription ?? "unknown"])
            )
            preconditionFailure("Migration error thrown for store of same version.")
        }
        #endif

        guard window.rootViewController?.presentedViewController == nil else { return }

        let compatibilityVersionMessage: String?
        if let mostRecentWorkingVersion = AppLaunchHistory.mostRecentWorkingVersionDescription {
            compatibilityVersionMessage = """
            \n\nYou previously had version \(mostRecentWorkingVersion), but now have version \
            \(BuildInfo.thisBuild.fullDescription). You will need to install \
            \(mostRecentWorkingVersion) again to be able to access your data.
            """
        } else {
            UserEngagement.logError(NSError(code: .noPreviousStoreVersionRecorded))
            compatibilityVersionMessage = nil
            assertionFailure("No recorded previously working version")
        }

        let alert = UIAlertController(title: "Incompatible Data", message: """
            The data on this device is not compatible with this version of Reading List.\(compatibilityVersionMessage ?? "")
            """, preferredStyle: .alert)

        #if DEBUG
        alert.addAction(UIAlertAction(title: "Delete Store", style: .destructive) { _ in
            NSPersistentStoreCoordinator().destroyAndDeleteStore(at: URL.applicationSupport.appendingPathComponent(PersistentStoreManager.storeFileName))
            self.initialisePersistentStore()
            self.storeMigrationFailed = false
        })
        #endif

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        window.rootViewController!.present(alert, animated: true)
    }
}

struct LaunchOptions {
    let url: URL?
    let quickAction: QuickAction?

    func any() -> Bool {
        return url != nil || quickAction != nil
    }
}
