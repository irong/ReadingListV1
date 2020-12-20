import Foundation
import UIKit
import CoreData
import ReadingList_Foundation
import ZIPFoundation
import os.log

struct BackupMarkerFileInfo: Codable, Equatable {
    let deviceName: String
    let deviceIdentifier: UUID
    let created: Date
    let deviceIdiom: UIUserInterfaceIdiom
    let modelVersion: String
    let sizeBytes: UInt64

    init(deviceIdentifier: UUID, size: UInt64) {
        self.deviceIdentifier = deviceIdentifier
        sizeBytes = size
        created = Date()
        deviceName = UIDevice.current.name
        modelVersion = BooksModelVersion.latest.rawValue
        deviceIdiom = UIDevice.current.userInterfaceIdiom
    }

    /**
     Returns wheter this backup should be considered a better backup to use than that provided.
     */
    func isPreferableTo(_ other: BackupMarkerFileInfo) -> Bool {
        let thisIsFromCurrentDevice = (deviceIdentifier == UIDevice.current.identifierForVendor)
        let otherIsFromCurrentDevice = (other.deviceIdentifier == UIDevice.current.identifierForVendor)
        if thisIsFromCurrentDevice && !otherIsFromCurrentDevice { return true }
        if !thisIsFromCurrentDevice && otherIsFromCurrentDevice { return false }
        return created < other.created
    }
}

extension UIUserInterfaceIdiom: Codable { }

struct BackupInfo: Equatable {
    let markerFileInfo: BackupMarkerFileInfo
    let url: URL
    let isDownloaded: Bool
    let isUploaded: Bool
}

enum BackupError: Error {
    case noCloudUser
    case noContainerUrl
    case noDeviceIdentifierAvailable
    case unsupportedVersion
}

class BackupManager {
    private let dispatchQueue = DispatchQueue(label: "BackupManager", qos: .userInitiated)
    private let backupInfoFileName = "backup.info"
    private let backupDataArchiveName = "data.zip"

    private let query: NSMetadataQuery
    private let operationQueue: OperationQueue
    private let deviceInstallBackupUuid: String
    private var notificationCenterObserver: NSObjectProtocol?

    init() {
        query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]

        operationQueue = OperationQueue()
        operationQueue.underlyingQueue = dispatchQueue
        operationQueue.maxConcurrentOperationCount = 1
        query.operationQueue = operationQueue

        // Use a generated, UserDefaults stored, UUID to identify backups from this install, so that app deletions and subsequent reinstalls
        // don't lead to subsequent backup overwrites.
        let userDefaultsKey = "BackupManager.DeviceIdentifier"
        if let deviceIdentifier = UserDefaults.standard.string(forKey: userDefaultsKey) {
            deviceInstallBackupUuid = deviceIdentifier
        } else {
            deviceInstallBackupUuid = UUID().uuidString
            UserDefaults.standard.set(deviceInstallBackupUuid, forKey: userDefaultsKey)
        }
    }

    deinit {
        stopWatchingForCloudChanges()
    }

    /**
     Returns the Backups directory within the app's iCloud UbiquityContainer. Do not call on the Main thread, as this may take some time to return a value.
     */
    private var backupsDirectory: URL? {
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Backups", isDirectory: true)
    }

    /**
     Returns the URL of the directory used as the current install's backup destination, within the app's iCloud UbiquityContainer. Do not call on the Main thread, as this may take some time to return a value.
     */
    private var currentInstallBackupDirectory: URL? {
        guard let backupsDirectory = backupsDirectory else { return nil }
        return URL(fileURLWithPath: deviceInstallBackupUuid, isDirectory: true, relativeTo: backupsDirectory)
    }

    /**
     Do not call from the Main thread.
     */
    func watchForCloudChanges() {
        // "In iOS, you must call this method at least once before trying to search for cloud-based files in the ubiquity container."
        FileManager.default.url(forUbiquityContainerIdentifier: nil)

        // Start observing query gathering completion
        notificationCenterObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [weak self] _ in
            guard let self = self else { return }
            self.dispatchQueue.async {
                self.metadataQueryGatheringComplete()
            }
        }
        query.start()
    }
    
    func stopWatchingForCloudChanges() {
        query.stop()
        if let notificationCenterObserver = notificationCenterObserver {
            NotificationCenter.default.removeObserver(notificationCenterObserver)
        }
    }

    @objc private func metadataQueryGatheringComplete() {
        os_log("Metadata query returned %d items", type: .info, query.results.count)
        if query.results.isEmpty { return }
        for queryResult in query.results {
            guard let resultItemMetadata = queryResult as? NSMetadataItem, let fileItemURL = resultItemMetadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                os_log("Unexpected query result type, or missing item URL", type: .error)
                continue
            }
            if let downloadStatus = resultItemMetadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
               downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // If the files are already downloaded then skip
                continue
            }

            do {
                os_log("Requesting download of query result %{public}s", type: .info, fileItemURL.path)
                try FileManager.default.startDownloadingUbiquitousItem(at: fileItemURL)
            } catch {
                os_log("Error starting download of iCloud item %{public}s", type: .error, fileItemURL.path)
            }
        }
    }

    /**
     Do not call from the Main thread. Returns info about all the backups which are visible in the backup directory in the cloud ubiquity container.
     */
    func readBackups() throws -> [BackupInfo] {
        guard FileManager.default.ubiquityIdentityToken != nil else { throw BackupError.noCloudUser }
        guard let backupsDirectory = backupsDirectory else { return [] }
        let backupsFolderContents = try FileManager.default.pathsWithinDirectory(backupsDirectory)

        var backupInfos = [BackupInfo]()
        for backupFolder in backupsFolderContents {
            // For each backup folder, get the backup marker file path - this file will contain info about the backup
            let backupMarkerFilePath = URL(fileURLWithPath: backupInfoFileName, relativeTo: backupFolder)
            do {
                let backupInfoData = try Data(contentsOf: backupMarkerFilePath)
                let backupInfo = try JSONDecoder().decode(BackupMarkerFileInfo.self, from: backupInfoData)
                backupInfos.append(BackupInfo(markerFileInfo: backupInfo, url: backupFolder, isDownloaded: false, isUploaded: false))
            } catch {
                os_log("Error getting backup info from file %{public}s: %{public}s", type: .error, backupFolder.path, error.localizedDescription)
                continue
            }
        }

        return backupInfos.sorted {
            $0.markerFileInfo.isPreferableTo($1.markerFileInfo)
        }
    }

    /**
     Replaces the current app's persistent store with that identified by the backup.
     Caution: calling this method required that no ManagedObjectContexts or ManagedObjects are in use throughout the app.
     */
    func restore(from backup: BackupInfo, completion: @escaping (Error?) -> Void) {
        // First, check that we recognise the backup's model version. It must not be a later version that
        // what this version of the app supports.
        guard let modelVersion = BooksModelVersion(rawValue: backup.markerFileInfo.modelVersion) else {
            completion(BackupError.unsupportedVersion)
            return
        }

        // Build the path to the persistent store file backup.
        let backupDataArchive = URL(fileURLWithPath: backupDataArchiveName, relativeTo: backup.url)
        let backupDataArchiveUnzipped = FileManager.default.createTemporaryDirectory()
        do {
            try FileManager.default.unzipItem(at: backupDataArchive, to: backupDataArchiveUnzipped)
        } catch {
            os_log("Error unzipping archive %{public}s: %{public}s", type: .error, backupDataArchive.path, error.localizedDescription)
            completion(error)
            return
        }
        let storeBackup = URL(fileURLWithPath: PersistentStoreManager.storeFileName, relativeTo: backupDataArchiveUnzipped)

        // Build a new persistent store coordinator to perform the move
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: modelVersion.managedObjectModel())

        // To be safe, we want to backup the current store to a temporary directory. If we can't, then don't go ahead with the restore.
        let currentStoreBackupDir = FileManager.default.createTemporaryDirectory()
        let currentStoreBackup = currentStoreBackupDir.appendingPathComponent(PersistentStoreManager.storeFileName)
        do {
            try PersistentStoreManager.container.copyPersistentStores(to: currentStoreBackup)
        } catch {
            os_log("Error creating current store backup: %{public}s", type: .error, error.localizedDescription)
            completion(error)
            return
        }

        do {
            // Replace the current store with that from our cloud backup
            try storeCoordinator.replacePersistentStore(
                at: PersistentStoreManager.storeLocation,
                destinationOptions: nil,
                withPersistentStoreFrom: storeBackup,
                sourceOptions: nil,
                ofType: NSSQLiteStoreType
            )

            // We now need to reinitialise the persistent store. This will replace the persistent container in use in the app,
            // and migrate the store (if necessary) to the current version.
            try PersistentStoreManager.initalisePersistentStore {
                // Clear out temporary files - the current-store backup, and the backup unzip directory
                try? FileManager.default.removeItem(at: currentStoreBackupDir)
                try? FileManager.default.removeItem(at: backupDataArchiveUnzipped)

                // If we get here, then we have successully restored!
                completion(nil)
            }
        } catch {
            // If we failed during the replacement of the store, then let's try to put the backup back in place, using the current (latest) managed object model.
            let restorationStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: BooksModelVersion.latest.managedObjectModel())
            do {
                try restorationStoreCoordinator.replacePersistentStore(
                    at: PersistentStoreManager.storeLocation,
                    destinationOptions: nil,
                    withPersistentStoreFrom: currentStoreBackup,
                    sourceOptions: nil,
                    ofType: NSSQLiteStoreType
                )

                try PersistentStoreManager.initalisePersistentStore {
                    // Clear out temporary files - the current-store backup, and the backup unzip directory
                    try? FileManager.default.removeItem(at: currentStoreBackupDir)
                    try? FileManager.default.removeItem(at: backupDataArchiveUnzipped)

                    // Remember that this does not represent success - we have succeeded in putting the backup back, but failed overall.
                    completion(error)
                }
            } catch {
                // This is a serious failure, and it's not clear what this means. The existing store may be OK, or it may be broken.
                // We can try to hope that the app remains functional.
                os_log("Error while attempting store recovery during backup restoration. The persistent store is now in an unknown state. %{public}s", type: .error, error.localizedDescription)

                // Clear out temporary files - the current-store backup, and the backup unzip directory
                try? FileManager.default.removeItem(at: currentStoreBackupDir)
                try? FileManager.default.removeItem(at: backupDataArchiveUnzipped)

                completion(error)
            }
        }
    }

    /**
     Performs a backup of the current store into the Backups iCloud directory.
     Do not call from the Main thread.
     */
    @discardableResult
    func performBackup() throws -> BackupInfo {
        guard let currentInstallBackupDirectory = currentInstallBackupDirectory else { throw BackupError.noContainerUrl }
        guard let deviceIdentifier = UIDevice.current.identifierForVendor else { throw BackupError.noDeviceIdentifierAvailable }

        // Get the target data directory
        let dataArchivePath = URL(fileURLWithPath: backupDataArchiveName, isDirectory: true, relativeTo: currentInstallBackupDirectory)
        os_log("Writing backup to %{public}s", dataArchivePath.path)

        // Ensure the backup directory exists
        try? FileManager.default.createDirectory(at: dataArchivePath, withIntermediateDirectories: true, attributes: nil)

        // Perform the backup
        let backupTemporaryLocation = FileManager.default.createTemporaryDirectory()
        try PersistentStoreManager.container.copyPersistentStores(to: backupTemporaryLocation, overwriting: false)
        try? FileManager.default.removeItem(at: dataArchivePath)
        try FileManager.default.zipItem(at: backupTemporaryLocation, to: dataArchivePath, shouldKeepParent: false)
        try? FileManager.default.removeItem(at: backupTemporaryLocation)

        // Now gather the data for the backup marker file
        let backupInfoURL = URL(fileURLWithPath: backupInfoFileName, relativeTo: currentInstallBackupDirectory)

        // Remove any existant item (if there is one)
        try? FileManager.default.removeItem(at: backupInfoURL)

        let backupSize: UInt64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dataArchivePath.path)
            if let sizeAttribute = attributes[.size] as? UInt64 {
                backupSize = sizeAttribute
            } else {
                os_log("Unexpected missing or non UInt64 size attribute", type: .error)
                backupSize = 0
            }
        } catch {
            os_log("Error calculating backup size on disk: %{public}s", type: .error, error.localizedDescription)
            backupSize = 0
        }

        // JSON encode the marker file info and write to the suitable file path
        let markerFileInfo = BackupMarkerFileInfo(deviceIdentifier: deviceIdentifier, size: backupSize)
        let markerFileData = try JSONEncoder().encode(markerFileInfo)
        try markerFileData.write(to: backupInfoURL)

        let isUploaded = (try? dataArchivePath.isUbiquitous()) ?? false
        return BackupInfo(markerFileInfo: markerFileInfo, url: currentInstallBackupDirectory, isDownloaded: true, isUploaded: isUploaded)
    }
}

extension URL {
    func isUbiquitous() throws -> Bool {
        var isUploadedResourceValue: AnyObject?
        try (self as NSURL).getResourceValue(&isUploadedResourceValue, forKey: URLResourceKey.isUbiquitousItemKey)
        guard let isUploadedResourceBoolean = isUploadedResourceValue as? NSNumber else { return false }
        return isUploadedResourceBoolean.boolValue
    }

    func isDownloaded() throws -> Bool {
        var isDownloadedResourceValue: AnyObject?
        try (self as NSURL).getResourceValue(&isDownloadedResourceValue, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
        guard let isDownloadedResourceString = isDownloadedResourceValue as? String else { return false }
        return isDownloadedResourceString == NSMetadataUbiquitousItemDownloadingStatusCurrent
    }
}
