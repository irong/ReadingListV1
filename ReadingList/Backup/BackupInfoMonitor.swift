import Foundation
import os.log

/// A utility which can watch for cloud changes to backup info files, and requests their download when they are detected.
final class BackupInfoMonitor {

    /// A global instance which is used to monitor for backup info file changes in the background.
    static let shared = BackupInfoMonitor()

    /// Is set to `true` when the initial set of backup info files are all reported to have been downloaded.
    private(set) var hasDownloadedAllInitialInfoFiles = false

    /// A utility dispatch queue upon which work is done.
    private let dispatchQueue = DispatchQueue(label: "com.andrewbennet.books.BackupInfoMonitor", qos: .utility)

    /// The metadata query which watches for backup.info files on iCloud.
    private let infoFilesQuery: NSMetadataQuery

    /// Set to the set of info file paths which are present when the metadata query first completes.
    private var initialInfoFiles: Set<URL>?

    /// Holds the last seen download state of all known backup info files, by their path.
    private var infoFilesDownloadState = [URL: Bool]()

    private init() {
        // Create a metadata query which will watch for the backup info files - these are small,
        // so quick to download and small enough for us to keep downloaded without worrying about
        // unnecessaily consuming local disk space.
        infoFilesQuery = NSMetadataQuery()
        infoFilesQuery.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        infoFilesQuery.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, BackupConstants.backupInfoFileName)

        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = dispatchQueue
        operationQueue.maxConcurrentOperationCount = 1
        infoFilesQuery.operationQueue = operationQueue
    }

    deinit {
        stop()
    }

    /**
     Starts the metadata query and registers observers for the notifications it sends.
     */
    func start() {
        os_log("Starting backup info cloud change observations")
        
        dispatchQueue.async {
            // "In iOS, you must call this method at least once before trying to search for cloud-based files in the ubiquity container."
            FileManager.default.url(forUbiquityContainerIdentifier: nil)

            // Start observing query gathering completion
            NotificationCenter.default.addObserver(self, selector: #selector(self.processQueryDidFinishGathering(_:)), name: .NSMetadataQueryDidFinishGathering, object: self.infoFilesQuery)
            NotificationCenter.default.addObserver(self, selector: #selector(self.processQueryUpdateOrProgress(_:)), name: .NSMetadataQueryDidUpdate, object: self.infoFilesQuery)
            NotificationCenter.default.addObserver(self, selector: #selector(self.processQueryUpdateOrProgress(_:)), name: .NSMetadataQueryGatheringProgress, object: self.infoFilesQuery)
            self.infoFilesQuery.start()
        }
    }

    /**
     Removes notification obsevers and stops the metadata query.
     */
    func stop() {
        os_log("Stopping backup info cloud change observations")

        infoFilesQuery.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: infoFilesQuery)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: infoFilesQuery)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryGatheringProgress, object: infoFilesQuery)
    }

    @objc private func processQueryDidFinishGathering(_ notification: Notification) {
        handleQueryNotification(isInitialGatheringCompletion: true)
    }

    @objc private func processQueryUpdateOrProgress(_ notification: Notification) {
        handleQueryNotification(isInitialGatheringCompletion: false)
    }

    private func handleQueryNotification(isInitialGatheringCompletion: Bool) {
        dispatchQueue.async {
            os_log("Metadata query returned %d items", type: .info, self.infoFilesQuery.resultCount)

            // If there are no info files at all, then we clear out our download state dictionary, and set the initial info files
            // array to empty (if it hasn't been set).
            if self.infoFilesQuery.resultCount == 0 {
                self.infoFilesDownloadState = [:]

                if isInitialGatheringCompletion {
                    os_log("Initial metadata query completed with 0 results; sending didDownloadInitialBackupInfoFiles notification")
                    self.initialInfoFiles = []

                    // Nothing to download, so we're done!
                    self.hasDownloadedAllInitialInfoFiles = true
                    NotificationCenter.default.post(name: .didDownloadInitialBackupInfoFiles, object: nil)
                }

                return
            }

            // If there are some results, enumerate through the indices.
            // We need to remember what files we saw, so we can remove anything else from the download state dictionary.
            var seenInfoFilePaths = Set<URL>()
            for resultIndex in 0..<self.infoFilesQuery.resultCount {
                guard let resultItemMetadata = self.infoFilesQuery.result(at: resultIndex) as? NSMetadataItem,
                      let fileItemURL = resultItemMetadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                    os_log("Unexpected query result type, or missing item URL", type: .error)
                    continue
                }
                seenInfoFilePaths.insert(fileItemURL)

                if let downloadStatus = resultItemMetadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
                   downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {

                    // If the file is newly downloaded, send a notification
                    if let existingDownloadState = self.infoFilesDownloadState[fileItemURL], !existingDownloadState {
                        os_log("File %{public}s is newly downloaded; posting notification", type: .info, fileItemURL.path)
                        NotificationCenter.default.post(name: .didDownloadNewBackupInfoFile, object: nil)
                    }
                    self.infoFilesDownloadState[fileItemURL] = true
                    continue
                }

                do {
                    os_log("Requesting download of query result %{public}s", type: .info, fileItemURL.path)
                    try FileManager.default.startDownloadingUbiquitousItem(at: fileItemURL)
                } catch {
                    os_log("Error starting download of iCloud item %{public}s", type: .error, fileItemURL.path)
                }
            }

            // Remember the set of file paths which were initially present, if this is the initial gather completion. This will be
            // used to track when all of the initial present files are downloaded, upon which event a notification will be pushed.
            if isInitialGatheringCompletion {
                assert(self.initialInfoFiles == nil)
                self.initialInfoFiles = seenInfoFilePaths
                os_log("Initial metadata query completed with %d results", self.infoFilesQuery.resultCount)
            }

            // If we've got a record of the initial set of files, and we haven't yet recorded that we've downloaded the initial
            // set of files, but we can see now that they are all downloaded, then flip the toggle and post a notification saying so.
            if let initialInfoFiles = self.initialInfoFiles,
               !self.hasDownloadedAllInitialInfoFiles,
               initialInfoFiles.allSatisfy({ self.infoFilesDownloadState[$0] ?? false }) {
                os_log("Initial set of info files are all downloaded; posting didDownloadInitialBackupInfoFiles notification")
                self.hasDownloadedAllInitialInfoFiles = true
                NotificationCenter.default.post(name: .didDownloadInitialBackupInfoFiles, object: nil)
            }

            // Clear out unseen files from our dictionary
            let unseenFilePaths = self.infoFilesDownloadState.filter { !seenInfoFilePaths.contains($0.key) }.map(\.key)
            for unseenFilePath in unseenFilePaths {
                self.infoFilesDownloadState.removeValue(forKey: unseenFilePath)
            }
        }
    }
}

extension Notification.Name {
    /// Posted when the initially present backup.info files are all downloaded.
    static let didDownloadInitialBackupInfoFiles = Notification.Name(rawValue: "didDownloadInitialBackupInfoFiles")

    /// Posted when any new backup.info file is downloaded.
    static let didDownloadNewBackupInfoFile = Notification.Name(rawValue: "didDownloadNewBackupInfoFile")
}
