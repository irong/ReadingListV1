import Foundation
import UIKit
import os.log

/// The possible states which a backup restoration may end with.
enum BackupRestoreResult {
    case success
    case failure(BackupManager.RestorationFailure)
    case cancelled
}

/// A view controller which manages a view, intended for full screen use, which displays a spinner and the text "Restoring..."
final class BackupRestoreProgress: UIViewController {
    fileprivate enum Mode {
        case downloading
        case restoring
    }

    convenience init(backupInfo: BackupInfo, completion: @escaping (BackupRestoreResult) -> Void) {
        self.init()
        self.backupInfo = backupInfo
        self.completion = completion
    }

    /// The backup to restore from.
    var backupInfo: BackupInfo!

    /// An action to take when the backup restoration is finished.
    var completion: ((BackupRestoreResult) -> Void)!

    private var restoringLabel: UILabel!
    private var cancelButton: UIButton!
    private var mode = Mode.restoring

    override func viewDidLoad() {
        super.viewDidLoad()

        startDownloadAndRestoreProcess()
        initialiseInterface()
    }

    // Backup download management
    private let downloadQueryDispatchQueue = DispatchQueue(label: "com.andrewbennet.books.BackupDownload", qos: .userInitiated)
    private lazy var downloadOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = self.downloadQueryDispatchQueue
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()
    private var backupDataFileQuery: NSMetadataQuery?

    private func startDownloadAndRestoreProcess() {
        let isDownloaded: Bool
        do {
            isDownloaded = try backupInfo.backupDataFilePath.isDownloaded()
        } catch {
            os_log("Could not determine whether file is downloaded: %{public}s", type: .error, error.localizedDescription)
            isDownloaded = false
        }
        mode = isDownloaded ? .restoring : .downloading

        if isDownloaded {
            os_log("Backup data is already downloaded: restoring")
            restoreData(using: backupInfo)
        } else {
            os_log("Backup data is not downloaded: downloading then restoring")
            downloadThenRestore(backup: backupInfo)
        }
    }

    private func stopAndRemoveQuery() {
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: backupDataFileQuery)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: backupDataFileQuery)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryGatheringProgress, object: backupDataFileQuery)
        self.backupDataFileQuery?.stop()
        self.backupDataFileQuery = nil
    }

    @objc private func checkDownloadProgress(_ notification: Notification) {
        guard let backupDataFileQuery = backupDataFileQuery else { return }
        let results = backupDataFileQuery.results
        guard results.count == 1, let metadataItem = results[0] as? NSMetadataItem else {
            os_log("MetadataQuery did not return a NSMetadataItem for the data archive", type: .error)
            completion(.failure(.missingDataArchive))
            return
        }
        guard let downloadingStatus = metadataItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String else {
            os_log("Could not get downloading status for metadata item", type: .error)
            return
        }

        os_log("Download status: %{public}s", type: .info, downloadingStatus)
        if downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
            os_log("Backup archive is downloaded; stopping query & restoring data...")
            stopAndRemoveQuery()

            #if DEBUG
            // For development ease, allow us to enter a mode where the downloading screen is held in place for a long time
            os_log("Debug setting stayOnBackupRestorationDownloadScreen is true; remaining on download view")
            if Debug.stayOnBackupRestorationDownloadScreen { return }
            #endif

            mode = .restoring
            // Update the UI to reflect that we are on the next stage of the restoration process
            DispatchQueue.main.async {
                self.restoringLabel.text = self.mode.description
                self.cancelButton.isHidden = true
            }

            restoreData(using: backupInfo)
        }
    }

    private func downloadThenRestore(backup: BackupInfo) {
        // A metadata query is used to watch the data archive file and detect when the file is locally available
        let downloadProgressQuery = NSMetadataQuery()
        downloadProgressQuery.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        downloadProgressQuery.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, backup.backupDataFilePath.path)
        NotificationCenter.default.addObserver(self, selector: #selector(checkDownloadProgress(_:)), name: .NSMetadataQueryDidFinishGathering, object: downloadProgressQuery)
        NotificationCenter.default.addObserver(self, selector: #selector(checkDownloadProgress(_:)), name: .NSMetadataQueryDidUpdate, object: downloadProgressQuery)
        NotificationCenter.default.addObserver(self, selector: #selector(checkDownloadProgress(_:)), name: .NSMetadataQueryGatheringProgress, object: downloadProgressQuery)
        downloadProgressQuery.operationQueue = downloadOperationQueue
        downloadProgressQuery.start()

        // Keep a reference to the query on self so that it is not deallocated once this function returns
        backupDataFileQuery = downloadProgressQuery

        // Kick off the download
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: backup.backupDataFilePath)
        } catch {
            self.completion(.failure(.missingDataArchive))
        }
    }

    private func restoreData(using backup: BackupInfo) {
        // Restore on a background thread
        downloadQueryDispatchQueue.async {
            BackupManager().restore(from: backup) { error in
                if let error = error {
                    os_log("Error restoring backup: %{public}s", type: .error, error.localizedDescription)
                    self.completion(.failure(error))
                    return
                }
                self.completion(.success)
            }
        }
    }

    @objc private func buttonAction(sender: UIButton) {
        stopAndRemoveQuery()
        completion(.cancelled)
    }

    /// Should only be called once, to set up the views.
    private func initialiseInterface() {
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        view.translatesAutoresizingMaskIntoConstraints = false

        // Text label to describe the operation
        let labelColor: UIColor
        if #available(iOS 13.0, *) {
            labelColor = .label
        } else {
            labelColor = .black
        }
        restoringLabel = UILabel(font: .preferredFont(forTextStyle: .body), color: labelColor, text: mode.description)
        restoringLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(restoringLabel)

        // Spinner which spins for the whole time this view is visible
        let spinnerStyle: UIActivityIndicatorView.Style
        if #available(iOS 13.0, *) {
            spinnerStyle = .large
        } else {
            spinnerStyle = .gray
        }
        let spinner = UIActivityIndicatorView(style: spinnerStyle)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        // A cancel button; sometimes hidden
        cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        guard let cancelButtonLabel = cancelButton.titleLabel else { preconditionFailure("Missing titleLabel on cancelButton") }
        cancelButtonLabel.font = .preferredFont(forTextStyle: .body)
        cancelButton.addTarget(self, action: #selector(buttonAction(sender:)), for: .touchUpInside)
        cancelButton.isHidden = mode == .restoring
        view.addSubview(cancelButton)

        // Configure the layout
        NSLayoutConstraint.activate([
            // Horizontally center the views...
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            restoringLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Vertically center the label, then position the spinner above and button below with some space
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            restoringLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            cancelButton.topAnchor.constraint(equalTo: restoringLabel.bottomAnchor, constant: 24)
        ])
    }
}

extension BackupRestoreProgress.Mode: CustomStringConvertible {
    var description: String {
        switch self {
        case .downloading: return "Downloading..."
        case .restoring: return "Restoring..."
        }
    }
}
