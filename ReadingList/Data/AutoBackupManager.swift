import Foundation
import PersistedPropertyWrapper
import BackgroundTasks
import os.log

enum BackupFrequencyPeriod: Int, CaseIterable {
    case daily = 1
    case weekly = 2
    case off = 0
}

extension BackupFrequencyPeriod {
    var duration: TimeInterval? {
        switch self {
        case .daily: return 60 * 60 * 24
        case .weekly: return 60 * 60 * 24 * 7
        case .off: return nil
        }
    }
}

class AutoBackupManager {
    @Persisted("backup-frequency-period", defaultValue: .daily)
    static var backupFrequency: BackupFrequencyPeriod

    @Persisted("last-backup-completion-date")
    static var lastBackupCompletion: Date?

    static let backgroundTaskIdentifier = "com.andrewbennet.books.backup"

    @available(iOS 13.0, *)
    class func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { preconditionFailure("Unexpected task type") }
            self.handleBackupTask(processingTask)
        }
    }

    @available(iOS 13.0, *)
    class func scheduleBackup(startingAfter earliestBeginDate: Date? = nil) {
        guard let backupInterval = backupFrequency.duration else { return }

        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        if let earliestBeginDate = earliestBeginDate {
            request.earliestBeginDate = earliestBeginDate
        } else if let lastBackup = lastBackupCompletion {
            request.earliestBeginDate = lastBackup.advanced(by: backupInterval)
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            os_log("Could not schedule app refresh: %{public}s", type: .error, error.localizedDescription)
        }
    }

    @available(iOS 13.0, *)
    class func handleBackupTask(_ task: BGProcessingTask) {
        // Schedule a new backup task
        if let backupInterval = backupFrequency.duration {
            scheduleBackup(startingAfter: Date(timeIntervalSinceNow: backupInterval))
        }

        let backupManager = BackupManager()
        do {
            try backupManager.performBackup()
            task.setTaskCompleted(success: true)
        } catch {
            os_log("Background backup task failed: %{public}s", type: .error, error.localizedDescription)
            task.setTaskCompleted(success: false)
        }
        lastBackupCompletion = Date()
    }
}
