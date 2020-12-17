import Foundation
import UIKit
import ReadingList_Foundation
import os.log
import SVProgressHUD

final class Backup: UITableViewController {
    private let backupManager = BackupManager()
    private var backupsInfo = [BackupInfo]()
    private var backupCreatedByThisController: BackupInfo?
    private var isWatchingForCloudChanges = false

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let refreshControl = self.refreshControl else { preconditionFailure("Missing refresh control") }
        refreshControl.addTarget(self, action: #selector(self.didPullToRefresh), for: .valueChanged)

        // This is an indication of whether the user is logged in to iCloud
        if FileManager.default.ubiquityIdentityToken != nil {
            DispatchQueue.global(qos: .userInitiated).async {
                self.backupManager.watchForCloudChanges()
                self.isWatchingForCloudChanges = true

                self.reloadBackupInfo()
            }
        }
    }

    @objc func didPullToRefresh() {
        tableView.isUserInteractionEnabled = false
        DispatchQueue.global(qos: .userInteractive).async {
            // If the user is logged in to iCloud but we are not watching for cloud changes yet, start doing so
            if FileManager.default.ubiquityIdentityToken != nil && !self.isWatchingForCloudChanges {
                self.backupManager.watchForCloudChanges()
                self.isWatchingForCloudChanges = true
            }

            self.reloadBackupInfo()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        // Ensure we use the latest backup frequency whenever this view appears (e.g. when the BackupFrequency view controller
        // pops back to this view).
        tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        // We don't show the backup history section if the user isn't logged in to iCloud, since they are likely to be stale
        return FileManager.default.ubiquityIdentityToken == nil ? 1 : 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return backupsInfo.isEmpty ? 1 : backupsInfo.count
        case 2: return 1
        default: fatalError("Unexpected call to numberOfRowsInSection for section \(section)")
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Backup"
        case 1: return "Restore"
        case 2: return "Auto-Backup"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            if FileManager.default.ubiquityIdentityToken == nil {
                return "App backup data is stored in iCloud. Ensure you are logged in to iCloud in order to back up your data."
            } else {
                return "Tap to backup the Reading List data on this device to iCloud."
            }
        case 1:
            if backupsInfo.isEmpty {
                return "App data backups will be listed here once they have been made. Note that it can take some time for backups made on other devices to sync with iCloud and appear here."
            } else {
                return "Tap a specific backup to restore the data on this device from a backup. Note that it can take some time for backups made on other devices to sync with iCloud and appear here."
            }
        case 2: return "Select the frequency that Reading List automatically backs up your data."
        default: return nil
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let byteFormatter = ByteCountFormatter()

    /// Dequeues and initialises a table view cell and initialises it with the current theme, if on earlier than iOS 13
    private func dequeueCell(withIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        cell.defaultInitialise(withTheme: GeneralSettings.theme)
        return cell
    }

    private let basicCellIdentifier = "BasicCell"
    private let subtitleCellIdentifier = "SubtitleCell"
    private let rightDetailCellIdentifier = "RightDetailCell"
    private let backupNowCellIndexPath = IndexPath(row: 0, section: 0)

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            return backupNowCell(indexPath)
        case 1:
            guard !backupsInfo.isEmpty else { return noBackupsAvailableCell(indexPath) }
            return backupInfoCell(at: indexPath)
        case 2:
            return backupFrequencyCell(indexPath)
        default: fatalError("Unexpected index path section \(indexPath.section)")
        }
    }

    private func backupNowCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueCell(withIdentifier: basicCellIdentifier, for: indexPath)
        guard let textLabel = cell.textLabel else { fatalError("Missing text label on cell") }
        if let backupCreatedByThisController = backupCreatedByThisController {
            cell.isEnabled = false
            textLabel.text = "Backup Created at \(dateFormatter.string(from: backupCreatedByThisController.markerFileInfo.created))"
            if #available(iOS 13.0, *) {
                textLabel.textColor = .secondaryLabel
            }
        } else if FileManager.default.ubiquityIdentityToken == nil {
            cell.isEnabled = false
            textLabel.text = "Log in to iCloud to Back Up"
            if #available(iOS 13.0, *) {
                textLabel.textColor = .secondaryLabel
            }
        } else {
            cell.isEnabled = true
            textLabel.text = "Back Up Now"
            textLabel.textColor = .systemBlue
        }
        return cell
    }

    private func noBackupsAvailableCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueCell(withIdentifier: basicCellIdentifier, for: indexPath)
        guard let textLabel = cell.textLabel else { fatalError("Missing text label on cell") }
        textLabel.text = "No Backups Available"
        if #available(iOS 13.0, *) {
            textLabel.textColor = .label
        }
        cell.isEnabled = false
        return cell
    }

    private func backupInfoCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueCell(withIdentifier: subtitleCellIdentifier, for: indexPath)
        guard let textLabel = cell.textLabel, let subtitleLabel = cell.detailTextLabel else { fatalError("Missing text label on cell") }
        let backup = backupsInfo[indexPath.row]
        textLabel.text = "\(backup.markerFileInfo.deviceName) (\(byteFormatter.string(fromByteCount: Int64(backup.markerFileInfo.sizeBytes))))"
        subtitleLabel.text = dateFormatter.string(from: backup.markerFileInfo.created)
        return cell
    }

    private func backupFrequencyCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueCell(withIdentifier: rightDetailCellIdentifier, for: indexPath)
        guard let textLabel = cell.textLabel, let rightDetailLabel = cell.detailTextLabel else { fatalError("Missing text label on cell") }
        textLabel.text = "Backup Frequency"
        rightDetailLabel.text = AutoBackupManager.shared.backupFrequency.description
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        if self.backupsInfo.isEmpty { return nil }
        return UISwipeActionsConfiguration(actions: [
            UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                let confirmation = UIAlertController(title: "Confirm Deletion", message: "Deleting this backup is irreversible. Are you sure you wish to delete this backup?", preferredStyle: .actionSheet)
                confirmation.addAction(UIAlertAction(title: "Delete Backup", style: .destructive) { _ in
                    do {
                        try FileManager.default.removeItem(at: self.backupsInfo[indexPath.row].url)
                    } catch {
                        // The most likely error is due to the file already being deleted; let's just act as if it was deleted,
                        // and it may come back when next refreshed...
                        os_log("Error deleting backup: %{public}s", type: .error, error.localizedDescription)
                    }

                    // Update the model then then table
                    let deletedBackup = self.backupsInfo.remove(at: indexPath.row)

                    // Restore the backup button if the user deleted the backup created by this view controller
                    if deletedBackup == self.backupCreatedByThisController {
                        self.backupCreatedByThisController = nil
                        tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                    }

                    if self.backupsInfo.isEmpty {
                        // Deleting the last row takes us from 1 row to 1 "No Backups" row, so just reload it
                        // rather than removing it.
                        tableView.reloadRows(at: [indexPath], with: .automatic)
                    } else {
                        tableView.deleteRows(at: [indexPath], with: .automatic)
                    }

                    completion(true)
                })
                confirmation.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                confirmation.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
                self.present(confirmation, animated: true)
            }
        ])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath == backupNowCellIndexPath {
            didSelectBackupNowCell()
        } else if indexPath.section == 1 {
            guard !self.backupsInfo.isEmpty else { return }
            let alert = UIAlertController(title: "Restore from Backup?", message: "Restoring from a backup will replace all current data with the data from the backup. Are you sure you wish to continue?", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Restore", style: .destructive) { _ in
                self.restore(from: self.backupsInfo[indexPath.row])
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
            present(alert, animated: true)
            tableView.deselectRow(at: indexPath, animated: true)
        } else if indexPath.section == 2 && indexPath.row == 0 {
            performSegue(withIdentifier: "presentBackupFrequency", sender: self)
        }
    }

    private func didSelectBackupNowCell() {
        guard FileManager.default.ubiquityIdentityToken != nil && backupCreatedByThisController == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.backupCreatedByThisController = try self.backupManager.performBackup()
            } catch {
                os_log("Error backing up: %{public}s", type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Error", message: "The backup could not be made. Please try again later.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }

            self.reloadBackupInfo()
        }
    }

    private func reloadBackupInfo() {
        let backups: [BackupInfo]
        do {
            backups = try self.backupManager.readBackups()
        } catch {
            os_log("Error reading backups: %{public}s", type: .error, error.localizedDescription)
            backups = []
        }

        DispatchQueue.main.async {
            self.backupsInfo = backups
            self.tableView.reloadData()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Ensure that any refresh control is ended, and the table is interactable. Wait half a second so the spinner doesn't vanish
                // before it is fully spinning
                self.refreshControl?.endRefreshing()
                self.tableView.isUserInteractionEnabled = true
            }
        }
    }

    private func restore(from backup: BackupInfo) {
        // This is a powerful function. We need to hot-replace the entire persistent store which is holding the app's data, while the app is running!
        // To do this, we need to deallocate all objects which are using managed objects or managed object contexts.
        guard let tabBarController = AppDelegate.shared.tabBarController else { preconditionFailure("No tab bar controller") }

        // Replace the first 3 tab bar controllers with dummy view controllers, so we keep the same tab bar appearance
        guard let lastVc = tabBarController.viewControllers?.last else { preconditionFailure("No tab bar view controllers present") }
        tabBarController.viewControllers = [UIViewController(), UIViewController(), UIViewController(), lastVc]
        tabBarController.configureTabIcons()

        // The SVProgressHUD blocks taps, so the user cannot navigate to these dummy view controllers
        DispatchQueue.main.async {
            SVProgressHUD.show(withStatus: "Restoring")
        }

        // Restore on a background thread, of course
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.backupManager.restoreFromBackup(backup: backup) { _ in
                    // Add half a second to the backup time, since it's so fast it is disconserting!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.restoreTabBarControllers()
                        SVProgressHUD.showSuccess(withStatus: "Restored")
                    }
                }
            } catch {
                os_log("Error restoring backup: %{public}s", type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    self.restoreTabBarControllers()
                    SVProgressHUD.showError(withStatus: "Could not restore from backup")
                }
            }
        }
    }

    private func restoreTabBarControllers() {
        guard let tabBarController = AppDelegate.shared.tabBarController else { preconditionFailure("No tab bar controller") }
        guard let lastVc = tabBarController.viewControllers?.last else { preconditionFailure("No last tab bar view controller") }

        // Get the new view controllers, but switch out the last one for the previous last one, which is the view controller
        // which holds the navigation stack which contains this view controller!
        var reinstantiatedViewControllers = tabBarController.getRootViewControllers()
        reinstantiatedViewControllers.removeLast()
        reinstantiatedViewControllers.append(lastVc)
        tabBarController.viewControllers = reinstantiatedViewControllers
        tabBarController.configureTabIcons()
    }
}
