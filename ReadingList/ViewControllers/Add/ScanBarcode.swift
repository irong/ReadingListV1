import UIKit
import AVFoundation
import SVProgressHUD
import ReadingList_Foundation
import CoreData
import os.log

class NonRotatingNavigationController: ThemedNavigationController {
    override var shouldAutorotate: Bool {
        // Correctly laying out the preview layer during interface rotation is tricky. Just disable it.
        return false
    }
}

class ScanBarcode: UIViewController {

    var session: AVCaptureSession?
    var metadataOutput: AVCaptureMetadataOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?

    var bulkAddedBooks = [Book]()
    var bulkAddLastScannedIsbn: String?

    /**
        Nil when not bulk adding, non-nil otherwise.
     */
    var bulkAddContext: NSManagedObjectContext?

    let feedbackGenerator = UINotificationFeedbackGenerator()
    let metadataObjectsDelegateQos = DispatchQueue.global(qos: .userInteractive)

    @IBOutlet private weak var torchButton: UIBarButtonItem!
    @IBOutlet private weak var scanManyButton: UIBarButtonItem!
    @IBOutlet private weak var reviewBooksButton: UIBarButtonItem!
    @IBOutlet private weak var cameraPreviewView: UIView!
    @IBOutlet private weak var previewOverlay: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch { } else {
            torchButton.setHidden(true)
        }

        feedbackGenerator.prepare()

        // To help with development, debug simulator builds detect taps on the screen and in response bring
        // up a dialog box to enter an ISBN to simulate a barcode scan.
        #if DEBUG && targetEnvironment(simulator)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onViewTap(_:))))
        #endif

        // Setup the camera preview asynchronously
        DispatchQueue.main.async {
            self.setupAvSession()
            self.previewOverlay.layer.borderColor = UIColor.red.cgColor
            self.previewOverlay.layer.borderWidth = 1.0
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    @objc func onViewTap(_ recognizer: UILongPressGestureRecognizer) {
        present(TextBoxAlert(title: "ISBN", initialValue: "978", keyboardType: .numberPad) {
            guard let isbn = $0 else { return }
            self.respondToCapturedIsbn(isbn)
        }, animated: true)
    }
    #endif

    @IBAction private func cancelWasPressed(_ sender: AnyObject) {
        SVProgressHUD.dismiss()
        if !bulkAddedBooks.isEmpty {
            let alert = UIAlertController(title: "Unsaved books", message: "You have \(bulkAddedBooks.count) unsaved \("book".pluralising(bulkAddedBooks.count)) which will be discarded if you cancel now. Are you sure?", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
                self.dismiss(animated: true)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            present(alert, animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @IBAction private func scanManyPressed(_ sender: UIBarButtonItem) {
        if bulkAddContext == nil {
            switchScanMode(toBulk: true)
        } else if bulkAddedBooks.isEmpty {
            switchScanMode(toBulk: false)
        } else {
            let alert = UIAlertController(
                title: "Discard \(bulkAddedBooks.count) \("book".pluralising(bulkAddedBooks.count))?",
                message: "You have already scanned \(bulkAddedBooks.count) \("book".pluralising(bulkAddedBooks.count)) which will be discarded if you switch to scanning a single book.",
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
                self.switchScanMode(toBulk: false)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            present(alert, animated: true)
        }
    }

    private func switchScanMode(toBulk bulk: Bool) {
        if bulk {
            bulkAddContext = PersistentStoreManager.container.viewContext.childContext()
            scanManyButton.title = "Scan Single"
            updateReviewBooksButton()
        } else {
            bulkAddContext = nil
            bulkAddedBooks.removeAll()
            bulkAddLastScannedIsbn = nil
            scanManyButton.title = "Scan Many"
            updateReviewBooksButton()
        }
    }

    @IBAction private func reviewBooksPressed(_ sender: UIBarButtonItem) {
        guard let bulkAddContext = bulkAddContext else { return }
        let reviewBooks = ReviewBulkBooks()
        reviewBooks.books = bulkAddedBooks
        reviewBooks.context = bulkAddContext
        present(reviewBooks, animated: true)
    }

    func updateReviewBooksButton() {
        if bulkAddContext == nil || bulkAddedBooks.isEmpty {
            reviewBooksButton.title = "Review Books"
            reviewBooksButton.isEnabled = false
        } else {
            reviewBooksButton.title = "Review \(bulkAddedBooks.count) \("Book".pluralising(bulkAddedBooks.count))"
            reviewBooksButton.isEnabled = true
        }
    }

    @IBAction private func torchPressed(_ sender: UIBarButtonItem) {
        switch AVCaptureDevice.toggleTorch() {
        case true:
            sender.image = #imageLiteral(resourceName: "TorchFilled")
        case false:
            sender.image = #imageLiteral(resourceName: "Torch")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraPreviewView.layoutIfNeeded()

        if let session = session, !session.isRunning {
            session.startRunning()
            metadataOutput?.setMetadataObjectsDelegate(self, queue: metadataObjectsDelegateQos)
        }

        navigationController?.setToolbarHidden(false, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let session = session, session.isRunning {
            session.stopRunning()
        }

        navigationController?.setToolbarHidden(true, animated: true)
    }

    private func setupAvSession() {
        #if DEBUG
        if CommandLine.arguments.contains("--UITests_Screenshots") {
            let imageView = UIImageView(frame: view.frame)
            imageView.contentMode = .scaleAspectFill
            imageView.image = #imageLiteral(resourceName: "example_barcode.jpg")
            view.addSubview(imageView)
            imageView.addSubview(previewOverlay)
            return
        }
        if let isbnToSimulate = UserDefaults.standard.string(forKey: "barcode-isbn-simulation") {
            respondToCapturedIsbn(isbnToSimulate)
            return
        }
        // We want to ignore any actual errors, like not having a camera, so return if UITesting
        if CommandLine.arguments.contains("--UITests") { return }
        #endif

        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera) else {
            #if !(DEBUG && targetEnvironment(simulator))
            presentCameraPermissionsAlert()
            #endif
            return
        }

        // Try to focus the camera if possible
        if camera.isFocusPointOfInterestSupported == true {
            try? camera.lockForConfiguration()
            camera.focusPointOfInterest = cameraPreviewView.center
        }

        metadataOutput = AVCaptureMetadataOutput()
        session = AVCaptureSession()

        // Check that we can add the input and output to the session
        guard let session = session, let metadataOutput = metadataOutput, session.canAddInput(input) && session.canAddOutput(metadataOutput) else {
            presentInfoAlert(title: "Error ⚠️", message: "The camera could not be used. Sorry about that.")
            feedbackGenerator.notificationOccurred(.error); return
        }

        // Prepare the metadata output and add to the session
        session.addInput(input)
        metadataOutput.setMetadataObjectsDelegate(self, queue: metadataObjectsDelegateQos)
        session.addOutput(metadataOutput)

        // This line must be after session outputs are added
        metadataOutput.metadataObjectTypes = [.ean13]

        // Begin the capture session.
        session.startRunning()

        // We want to view what the camera is seeing
        previewLayer = AVCaptureVideoPreviewLayer(session, gravity: .resizeAspectFill, frame: view.bounds)
        setVideoOrientation()

        cameraPreviewView.layer.addSublayer(previewLayer!)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        setVideoOrientation()
    }

    private func setVideoOrientation() {
        guard let connection = previewLayer?.connection, connection.isVideoOrientationSupported else { return }

        if let videoOrientation = UIDevice.current.orientation.videoOrientation {
            connection.videoOrientation = videoOrientation
        }
    }

    func respondToCapturedIsbn(_ isbn: String) {
        feedbackGenerator.prepare()

        // If we are bulk adding books, ensure that this isn't the most recently scanned book
        if bulkAddContext != nil {
            if isbn == bulkAddLastScannedIsbn {
                // Don't even give a warning: re-scanning the last ISBN can be done very easily
                return
            } else {
                // Remember that we have seen this ISBN
                bulkAddLastScannedIsbn = isbn
            }
        }

        // Since we have a result, stop the metadata capture
        metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)

        // Check that the book hasn't already been added
        if let existingBook = Book.get(fromContext: PersistentStoreManager.container.viewContext, isbn: isbn) {
            feedbackGenerator.notificationOccurred(.warning)
            handleDuplicateBook(existingBook)
        } else if let existingBulkBook = bulkAddedBooks.first(where: { $0.isbn13?.string == isbn }) {
            feedbackGenerator.notificationOccurred(.warning)
            handleDuplicateBook(existingBulkBook)
        } else {
            feedbackGenerator.notificationOccurred(.success)
            searchForFoundIsbn(isbn: isbn)
        }
    }

    func handleDuplicateBook(_ book: Book) {
        if bulkAddContext != nil {
            SVProgressHUD.showError(withStatus: "Already Added")
            metadataOutput?.setMetadataObjectsDelegate(self, queue: self.metadataObjectsDelegateQos)
            return
        }
        let alert = UIAlertController.duplicateBook(goToExistingBook: {
            self.dismiss(animated: true) {
                guard let tabBarController = AppDelegate.shared.tabBarController else {
                    assertionFailure()
                    return
                }
                tabBarController.simulateBookSelection(book, allowTableObscuring: true)
            }
        }, cancel: {
            self.metadataOutput?.setMetadataObjectsDelegate(self, queue: self.metadataObjectsDelegateQos)
        })

        present(alert, animated: true)
    }

    func searchForFoundIsbn(isbn: String) {
        // We're going to be doing a search online, so bring up a spinner
        SVProgressHUD.show(withStatus: "Searching...")

        GoogleBooks.fetch(isbn: isbn)
            .always(on: .main) { SVProgressHUD.dismiss() }
            .catch(on: .main) { error in
                self.feedbackGenerator.notificationOccurred(.error)
                switch error {
                case GoogleError.noResult: self.handleNoExactMatch(forIsbn: isbn)
                default: self.onSearchError(error)
                }
            }
            .then(on: .main, handleFetchSuccess(_:))
    }

    func handleFetchSuccess(_ fetchResult: FetchResult) {
        if let existingBook = Book.get(fromContext: bulkAddContext ?? PersistentStoreManager.container.viewContext, googleBooksId: fetchResult.id) {
            self.feedbackGenerator.notificationOccurred(.warning)
            self.handleDuplicateBook(existingBook)
            return
        }

        self.feedbackGenerator.notificationOccurred(.success)

        // If there is no duplicate, we can safely proceed. The context we add the book to depends on the
        // mode we are operating in.
        let context = self.bulkAddContext ?? PersistentStoreManager.container.viewContext.childContext()
        let book = Book(context: context)
        book.populate(fromFetchResult: fetchResult)

        if self.bulkAddContext == nil {
            UserEngagement.logEvent(.scanBarcode)

            // If we are just adding one book, we push to the screen to edit the read state of this book
            self.navigationController?.pushViewController(
                EditBookReadState(newUnsavedBook: book, scratchpadContext: context),
                animated: true)
        } else {
            UserEngagement.logEvent(.scanBarcodeBulk)

            // If we are in Bulk Add mode, set the book to To Read for now then add the book to our array
            book.setToRead()
            book.updateSortIndex()
            self.bulkAddedBooks.append(book)

            // Update the toolbar button and restart the metadata capture
            self.updateReviewBooksButton()
            self.metadataOutput?.setMetadataObjectsDelegate(self, queue: self.metadataObjectsDelegateQos)
        }
    }

    func handleNoExactMatch(forIsbn isbn: String) {
        // We don't want to give the user the option of leaving this screen and entering a new workflow if they
        // are in the middle of a bulk barcode scan operation.
        if bulkAddContext != nil {
            SVProgressHUD.showError(withStatus: "No Match Found")
            self.metadataOutput?.setMetadataObjectsDelegate(self, queue: self.metadataObjectsDelegateQos)
            return
        }
        let alert = UIAlertController(title: "No Exact Match",
                                      message: "We couldn't find an exact match. Would you like to do a more general search instead?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "No", style: .cancel) { _ in
            self.metadataOutput?.setMetadataObjectsDelegate(self, queue: self.metadataObjectsDelegateQos)
        })
        alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
            let presentingViewController = self.presentingViewController
            self.dismiss(animated: true) {
                let searchOnlineNav = UIStoryboard.SearchOnline.rootAsFormSheet() as! UINavigationController
                (searchOnlineNav.viewControllers.first as! SearchOnline).initialSearchString = isbn
                presentingViewController!.present(searchOnlineNav, animated: true, completion: nil)
            }
        })
        present(alert, animated: true, completion: nil)
    }

    func onSearchError(_ error: Error) {
        let message: String
        switch (error as NSError).code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            message = "There seems to be no internet connection."
        default:
            message = "Something went wrong when searching online. Maybe try again?"
        }
        presentInfoAlert(title: "Error ⚠️", message: message)
    }

    func presentInfoAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.dismiss(animated: true, completion: nil)
        })
        present(alert, animated: true, completion: nil)
    }

    func presentCameraPermissionsAlert() {
        let alert = UIAlertController(title: "Permission Required", message: "You'll need to change your settings to allow Reading List to use your device's camera.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let appSettings = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(appSettings) {
                UIApplication.shared.open(appSettings, options: [:])
                self.dismiss(animated: false)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.dismiss(animated: true)
        })
        feedbackGenerator.notificationOccurred(.error)
        present(alert, animated: true, completion: nil)
    }
}

extension ScanBarcode: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let avMetadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let isbn = ISBN13(avMetadata.stringValue) else { return }

        DispatchQueue.main.async {
            self.respondToCapturedIsbn(isbn.string)
        }
    }
}
