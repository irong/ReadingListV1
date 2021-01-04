import Foundation
import SwiftyStoreKit
import SVProgressHUD
import os.log
import CoreData
import ReadingList_Foundation
import PersistedPropertyWrapper

class LaunchManager {

    init(window: UIWindow?) {
        self.window = window
    }

    let window: UIWindow?
    var storeMigrationFailed = false
    var isFirstLaunch = false

    /**
     Performs any required initialisation immediately post after the app has launched.
     This must be called prior to any other initialisation actions.
    */
    func initialise() {
        isFirstLaunch = AppLaunchHistory.appOpenedCount == 0
        #if DEBUG
        Debug.initialiseSettings()
        #endif
        UserEngagement.initialiseUserAnalytics()
        SVProgressHUD.setDefaults()
        SwiftyStoreKit.completeTransactions()
        BackupInfoMonitor.shared.start()
        if #available(iOS 13.0, *) {
            AutoBackupManager.shared.registerBackgroundTasks()
            AutoBackupManager.shared.scheduleBackup()
        }
    }

    func handleApplicationDidBecomeActive() {
        AppLaunchHistory.appOpenedCount += 1

        if storeMigrationFailed {
            presentIncompatibleDataAlert()
        }
    }

    enum LegacyBackupError: Int, Error {
        case timeoutExpired = 0
    }

    func handleApplicationDidEnterBackground() {
        // The only use of this lifecycle method is to run background backups, on iOS 12 where we don't have access
        // to the newer background task scheduling functionality.
        if #available(iOS 13.0, *) { return }

        // Determine whether we ought to backup now
        guard AutoBackupManager.shared.backupIsDue() else { return }

        let taskIdentifier = UIApplication.shared.beginBackgroundTask {
            // Expiration handler: if we didn't get enough time to complete the backup, log an error
            UserEngagement.logError(LegacyBackupError.timeoutExpired)
            os_log("Expiration Handler called for background backup task", type: .error)
            AutoBackupManager.shared.lastAutoBackupFailed = true
        }
        os_log("Running background task to perform data backup. %d seconds background time available.", UIApplication.shared.backgroundTimeRemaining)

        // Run the backup in the background. Use `.userInitiated` to help us finish the backup slightly faster.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try BackupManager().performBackup()

                os_log("Background backup task completed")
                UserEngagement.logEvent(.autoBackup)
                AutoBackupManager.shared.lastAutoBackupFailed = false
            } catch {
                os_log("Backup failed: %{public}s", type: .error, error.localizedDescription)
                UserEngagement.logError(error)
            }

            AutoBackupManager.shared.lastBackupCompletion = Date()
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }

    func extractRelevantLaunchOptions(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> LaunchOptions {
        let quickAction: QuickAction?
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            quickAction = QuickAction(rawValue: shortcut.type)
        } else {
            quickAction = nil
        }

        return LaunchOptions(url: launchOptions?[.url] as? URL, quickAction: quickAction)
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
        guard let window = window else { return }
        guard let tabBarController = window.rootViewController as? TabBarController else {
            assertionFailure()
            return
        }

        if let quickAction = options.quickAction {
            quickAction.perform(from: tabBarController)
        } else if let launchUrl = options.url {
            self.handleOpenUrl(launchUrl)
        }
    }

    /**
     Returns whether the provided URL could be handled.
    */
    @discardableResult func handleOpenUrl(_ url: URL) -> Bool {
        guard let window = window else { return false }
        if url.isFileURL && url.pathExtension == "csv" {
            return openCsvFileInApp(url: url)
        } else if url.scheme == ProprietaryURLManager.scheme {
            if let urlAction = ProprietaryURLManager().getAction(from: url) {
                return ProprietaryURLActionHandler(window: window).handle(urlAction)
            } else {
                os_log("Unparsable URL: %{public}s", type: .error, url.absoluteString)
                return false
            }
        } else {
            os_log("Unrecognised URL type; handling not possible: %{public}s", type: .error, url.absoluteString)
            return false
        }
    }

    private func openCsvFileInApp(url: URL) -> Bool {
        os_log("Opening CSV file URL: %{public}s", type: .default, url.absoluteString)

        guard let tabBarController = window?.rootViewController as? TabBarController else {
            fatalError("Missing root tab bar controller")
        }
        UserEngagement.logEvent(.openCsvInApp)
        tabBarController.presentImportExportView(importUrl: url)
        return true
    }

    func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let quickAction = QuickAction(rawValue: shortcutItem.type) else { return false }
        guard let tabBarController = window?.rootViewController as? TabBarController else { return false }
        quickAction.perform(from: tabBarController)
        return true
    }

    var presentFirstLaunchOrChangeLog: Bool {
        #if DEBUG
        return !CommandLine.arguments.contains("--UITests_Screenshots")
        #else
        return true
        #endif
    }

    private func initialiseAfterPersistentStoreLoad() {
        #if DEBUG
        Debug.initialiseData()
        #endif

        guard let window = window else { return }
        let rootViewController = TabBarController()
        window.rootViewController = rootViewController

        // Initialise app-level theme, and monitor the set theme, if < iOS 13
        if #available(iOS 13.0, *) { } else {
            initialiseTheme()
            NotificationCenter.default.addObserver(self, selector: #selector(self.initialiseTheme), name: .ThemeSettingChanged, object: nil)
        }

        if #available(iOS 14.0, *) {
            BookDataSharer.instance.inititialise(persistentContainer: PersistentStoreManager.container)
            if AppLaunchHistory.lastLaunchedBuildInfo?.buildNumber != BuildInfo.thisBuild.buildNumber || BuildInfo.thisBuild.type == .debug {
                // Not strictly a save, but the first time we launch an updated version of the app, we ought to repopulate the shared book data
                os_log("Repopulating shared book data for widget", type: .default)
                BookDataSharer.instance.handleChanges(forceUpdate: true)
            }
        }

        if presentFirstLaunchOrChangeLog {
            if isFirstLaunch {
                let firstOpenScreen = FirstOpenScreenProvider().build {
                    FirstLaunchRestorationManager.shared.presentRestorePromptIfSuitableBackupFound()
                }
                rootViewController.present(firstOpenScreen, animated: true)
            } else if let lastLaunchedVersion = AppLaunchHistory.lastLaunchedBuildInfo?.version {
                if let changeList = ChangeListProvider().changeListController(after: lastLaunchedVersion) {
                    rootViewController.present(changeList, animated: true)
                }
            }
        }

        AppLaunchHistory.lastLaunchedBuildInfo = BuildInfo.thisBuild
    }

    @available(iOS, obsoleted: 13.0)
    @objc private func initialiseTheme() {
        if #available(iOS 13.0, *) { return }
        let theme = GeneralSettings.theme
        theme.configureForms()
        window?.tintColor = theme.tint
    }

    private func presentIncompatibleDataAlert() {
        guard let window = window else { fatalError("No window present when attempting to present an incompatible data alert") }

        #if RELEASE
        // This is a common error during development, but shouldn't occur in production
        guard AppLaunchHistory.lastLaunchedBuildInfo?.version != BuildInfo.thisBuild.version else {
            fatalError("Migration error thrown for store of same version. Most recent working version: \(AppLaunchHistory.lastLaunchedBuildInfo?.fullDescription ?? "unknown")")
        }
        #endif

        guard window.rootViewController?.presentedViewController == nil else { return }

        let compatibilityVersionMessage: String?
        if let mostRecentWorkingVersion = AppLaunchHistory.lastLaunchedBuildInfo?.fullDescription {
            compatibilityVersionMessage = """
            \n\nYou previously had version \(mostRecentWorkingVersion), but now have version \
            \(BuildInfo.thisBuild.fullDescription). You will need to install \
            \(mostRecentWorkingVersion) again to be able to access your data.
            """
        } else {
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
