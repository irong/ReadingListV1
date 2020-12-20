import Foundation
import UIKit
import os.log

class BackupRestorationManager {
    init(window: UIWindow) {
        self.window = window
    }

    private let window: UIWindow
    private let backupManager = BackupManager()

    func startDownloadingBackupInfo() {
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            self.backupManager.watchForCloudChanges()
        }
    }

    func presentRestorePromptIfSuitableBackupFound() {
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        // TODO: This has a timing issue: ideally we could have a way to poll to see when the downloaded files are ready yet.
        checkForBackupForRestoration { backupInfo in
            DispatchQueue.main.async {
                guard let rootViewController = self.window.rootViewController else { return }
                let restorationAlert = self.restoreFromBackupAlert(backupInfo)
                rootViewController.present(restorationAlert, animated: true)
            }
        }
    }

    func checkForBackupForRestoration(completion: @escaping (BackupInfo) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.backupManager.stopWatchingForCloudChanges()
            let backups: [BackupInfo]
            do {
                backups = try self.backupManager.readBackups()
            } catch {
                os_log("Error reading backups: %{public}s", type: .error, error.localizedDescription)
                return
            }

            if backups.isEmpty {
                os_log("No backups found to use for first-launch restoration")
                return
            }

            // We only prompt if we found a backup from the same device class as this one. We don't intend for backups
            // to be used as a means to transfer data between iPhone and iPad, rather as a means to restore data from
            // one device to the same device (after a reinstall) or its replacement.
            if let backup = backups.filter({ $0.markerFileInfo.deviceIdiom == UIDevice.current.userInterfaceIdiom })
                .min(by: { left, right in
                    return left.markerFileInfo.isPreferableTo(right.markerFileInfo)
                }) {
                os_log("Found candidate backup to propose restoration")
                completion(backup)
            } else {
                os_log("No backups matched requirements to propose backup restoration")
            }
        }
    }

    func performRestore(from backup: BackupInfo) {
        window.rootViewController = BackupPlaceholderViewController()

        // Restore on a background thread, but capture the window here first
        let window = self.window
        DispatchQueue.global(qos: .userInitiated).async {
            self.backupManager.restore(from: backup) { error in
                if let error = error {
                    os_log("Error restoring backup: %{public}s", type: .error, error.localizedDescription)
                }
                // Add some time, since it can run so fast that it is disconserting!
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let tabBarController = TabBarController()
                    window.rootViewController = tabBarController

                    if let error = error {
                        let alertMessage: String
                        if error as? BackupError == BackupError.unsupportedVersion {
                            alertMessage = "The backup was made using a newer verion of Reading List. Please upgrade the app and try again."
                        } else {
                            UserEngagement.logError(error)
                            alertMessage = "An error occurred restoring from the backup."
                        }
                        let alert = UIAlertController(title: "Restoration Failed", message: alertMessage, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        tabBarController.present(alert, animated: true)
                    }
                }
            }
        }
    }

    func restoreFromBackupAlert(_ backupInfo: BackupInfo) -> UIAlertController {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let alert = UIAlertController(
            title: "Restore from Backup?",
            message: """
            A data backup made on \(dateFormatter.string(from: backupInfo.markerFileInfo.created)) on \
            \(backupInfo.markerFileInfo.deviceName) was found. Do you want to restore the data from the backup?
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Restore", style: .destructive) { _ in
            self.performRestore(from: backupInfo)
        })
        alert.addAction(UIAlertAction(title: "More Info", style: .default) { _ in
            guard let tabBarController = AppDelegate.shared.tabBarController else { fatalError("Missing tab bar controller") }
            tabBarController.presentBackupView()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        return alert
    }
}

/// A view controller which manages a view, intended for full screen use, which displays a spinner and the text "Restoring..."
class BackupPlaceholderViewController: UIViewController {
    private var backgroundColor: UIColor {
        if #available(iOS 13.0, *) {
            return .systemBackground
        } else {
            return .white
        }
    }

    private var labelColor: UIColor {
        if #available(iOS 13.0, *) {
            return .label
        } else {
            return .black
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor
        view.translatesAutoresizingMaskIntoConstraints = false
        let restoringLabel = UILabel(font: .preferredFont(forTextStyle: .body), color: labelColor, text: "Restoring...")
        restoringLabel.translatesAutoresizingMaskIntoConstraints = false
        let spinnerStyle: UIActivityIndicatorView.Style
        if #available(iOS 13.0, *) {
            spinnerStyle = .large
        } else {
            spinnerStyle = .gray
        }
        let spinner = UIActivityIndicatorView(style: spinnerStyle)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(restoringLabel)
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            restoringLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            restoringLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12)
        ])
    }
}
