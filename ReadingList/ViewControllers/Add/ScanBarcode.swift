import UIKit
import AVFoundation
import SVProgressHUD
import ReadingList_Foundation

class NonRotatingNavigationController: ThemedNavigationController {
    override var shouldAutorotate: Bool {
        // Correctly laying out the preview layer during interface rotation is tricky. Just disable it.
        return false
    }
}

class ScanBarcode: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    let feedbackGenerator = UINotificationFeedbackGenerator()

    @IBOutlet private weak var cameraPreviewView: UIView!
    @IBOutlet private weak var previewOverlay: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        feedbackGenerator.prepare()

        // Setup the camera preview asynchronously
        DispatchQueue.main.async {
            self.setupAvSession()
            self.previewOverlay.layer.borderColor = UIColor.red.cgColor
            self.previewOverlay.layer.borderWidth = 1.0
        }
    }

    @IBAction private func cancelWasPressed(_ sender: AnyObject) {
        SVProgressHUD.dismiss()
        dismiss(animated: true, completion: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        cameraPreviewView.layoutIfNeeded()

        if session?.isRunning == false {
            session!.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if session?.isRunning == true {
            session!.stopRunning()
        }
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

        guard let camera = AVCaptureDevice.default(for: AVMediaType.video), let input = try? AVCaptureDeviceInput(device: camera) else {
            presentCameraPermissionsAlert(); return
        }

        // Try to focus the camera if possible
        if camera.isFocusPointOfInterestSupported == true {
            try? camera.lockForConfiguration()
            camera.focusPointOfInterest = cameraPreviewView.center
        }

        let output = AVCaptureMetadataOutput()
        session = AVCaptureSession()

        // Check that we can add the input and output to the session
        guard session!.canAddInput(input) && session!.canAddOutput(output) else {
            presentInfoAlert(title: "Error ⚠️", message: "The camera could not be used. Sorry about that.")
            feedbackGenerator.notificationOccurred(.error); return
        }

        // Prepare the metadata output and add to the session
        session!.addInput(input)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
        session!.addOutput(output)

        // This line must be after session outputs are added
        output.metadataObjectTypes = [.ean13]

        // Begin the capture session.
        session!.startRunning()

        // We want to view what the camera is seeing
        previewLayer = AVCaptureVideoPreviewLayer(session: session!)
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer!.frame = view.bounds
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

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let avMetadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let isbn = ISBN13(avMetadata.stringValue) else { return }
        DispatchQueue.main.sync {
            respondToCapturedIsbn(isbn.string)
        }
    }

    func respondToCapturedIsbn(_ isbn: String) {
        feedbackGenerator.prepare()

        // Since we have a result, stop the session and hide the preview
        session?.stopRunning()

        // Check that the book hasn't already been added
        if let existingBook = Book.get(fromContext: PersistentStoreManager.container.viewContext, isbn: isbn) {
            feedbackGenerator.notificationOccurred(.warning)
            presentDuplicateAlert(existingBook)
        } else {
            feedbackGenerator.notificationOccurred(.success)
            searchForFoundIsbn(isbn: isbn)
        }
    }

    func presentDuplicateAlert(_ book: Book) {
        let alert = UIAlertController.duplicateBook(goToExistingBook: {
            self.dismiss(animated: true) {
                guard let tabBarController = AppDelegate.shared.tabBarController else {
                    assertionFailure()
                    return
                }
                tabBarController.simulateBookSelection(book, allowTableObscuring: true)
            }
        }, cancel: {
            self.session?.startRunning()
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
                case GoogleError.noResult: self.presentNoExactMatchAlert(forIsbn: isbn)
                default: self.onSearchError(error)
                }
            }
            .then(on: .main) { fetchResult in
                guard let navigationController = self.navigationController else { return }

                if let existingBook = Book.get(fromContext: PersistentStoreManager.container.viewContext, googleBooksId: fetchResult.id) {
                    self.feedbackGenerator.notificationOccurred(.warning)
                    self.presentDuplicateAlert(existingBook)
                } else {
                    self.feedbackGenerator.notificationOccurred(.success)

                    // Event logging
                    UserEngagement.logEvent(.scanBarcode)

                    // If there is no duplicate, we can safely go to the next page
                    let context = PersistentStoreManager.container.viewContext.childContext()
                    let book = Book(context: context)
                    book.populate(fromFetchResult: fetchResult)
                    navigationController.pushViewController(
                        EditBookReadState(newUnsavedBook: book, scratchpadContext: context),
                        animated: true)
                }
            }
    }

    func presentNoExactMatchAlert(forIsbn isbn: String) {
        let alert = UIAlertController(title: "No Exact Match",
                                      message: "We couldn't find an exact match. Would you like to do a more general search instead?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "No", style: .cancel) { _ in
            self.session?.startRunning()
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
        var message: String!
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
