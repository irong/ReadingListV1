import Foundation
import ReadingList_Foundation
import PersistedPropertyWrapper
import UIKit
import SVProgressHUD

final class Import: UITableViewController {
    @IBOutlet private weak var downloadMetadataSwitch: UISwitch!
    @IBOutlet private weak var downloadCoversSwitch: UISwitch!
    @IBOutlet private weak var overwriteExistingSwitch: UISwitch!
    @IBOutlet private weak var importFormatDescription: UILabel!

    @Persisted(encodedDataKey: "importFormat", defaultValue: .readingList)
    private var importFormat: ImportCsvFormat {
        didSet {
            importFormatDescription.text = importFormat.description
        }
    }

    @Persisted(encodedDataKey: "importSettings", defaultValue: .init())
    var importSettings: ImportSettings

    override func viewDidLoad() {
        super.viewDidLoad()
        monitorThemeSetting()
        navigationItem.title = "Import From CSV"
        downloadMetadataSwitch.isOn = importSettings.downloadMetadata
        downloadCoversSwitch.isOn = importSettings.downloadCoverImages
        overwriteExistingSwitch.isOn = importSettings.overwriteExistingBooks
        importFormatDescription.text = importFormat.description
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        if #available(iOS 13.0, *) { } else {
            cell.defaultInitialise(withTheme: GeneralSettings.theme)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath == IndexPath(row: 0, section: 0) {
            let alert = UIAlertController(title: "Select Import Format", message: nil, preferredStyle: .actionSheet)
            alert.addActions(ImportCsvFormat.allCases.map { format in
                UIAlertAction(title: format.description, style: .default) { _ in
                    self.importFormat = format
                }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
            present(alert, animated: true)
        } else if indexPath == IndexPath(row: 1, section: 0) {
            switch importFormat {
            case .readingList:
                performSegue(withIdentifier: "showFormatDetails", sender: self)
            case .goodreads:
                performSegue(withIdentifier: "showGoodreadsInfo", sender: self)
            }
        } else if indexPath == IndexPath(row: 0, section: 2) {
            presentDocumentPicker(presentingIndexPath: indexPath)
        } else {
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    @IBAction private func downloadMetadataChanged(_ sender: UISwitch) {
        importSettings.downloadMetadata = sender.isOn
    }

    @IBAction private func downloadCoversChanged(_ sender: UISwitch) {
        importSettings.downloadCoverImages = sender.isOn
    }

    @IBAction private func overwriteExistingBooksChanged(_ sender: UISwitch) {
        importSettings.overwriteExistingBooks = sender.isOn
    }

    let explanationHeader: [ImportCsvFormat: String] = [
        .readingList: "Import from a CSV file to create multiple books at once, or to move data from one device to another.",
        .goodreads: "Import from a Goodreads export to move your books and lists over from Goodreads."
    ]

    func presentDocumentPicker(presentingIndexPath: IndexPath) {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.comma-separated-values-text"], in: .import)
        documentPicker.delegate = self
        documentPicker.popoverPresentationController?.setSourceCell(atIndexPath: presentingIndexPath, inTable: tableView, arrowDirections: .up)
        present(documentPicker, animated: true)
    }

    func confirmImport(fromFile url: URL) {
        let alert = UIAlertController(title: "Confirm Import", message: """
            Are you sure you want to import books from this file?
            """, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Import", style: .default) { _ in
            SVProgressHUD.show(withStatus: "Importing")
            UserEngagement.logEvent(.csvImport)

            let csvImporter = BookCSVImporter(format: self.importFormat, settings: self.importSettings)
            csvImporter.startImport(fromFileAt: url) { result in
                switch result {
                case .failure(let error):
                    SVProgressHUD.dismiss()
                    self.presentCsvErrorAlert(error)
                case .success(let importResults):
                    var statusMessagePieces = ["\(importResults.success) books imported"]
                    if importResults.duplicate != 0 { statusMessagePieces.append("\(importResults.duplicate) rows ignored due pre-existing data") }
                    if importResults.error != 0 { statusMessagePieces.append("\(importResults.error) rows ignored due to invalid data") }
                    SVProgressHUD.showInfo(withStatus: statusMessagePieces.joined(separator: ". "))
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true)
    }

    func presentCsvErrorAlert(_ error: CSVImportError) {
        let title = error == .invalidCsv ? "Invalid CSV File" : "Missing CSV Columns"
        let reason = error == .invalidCsv ? "not valid" : "missing required columns"
        let alert = UIAlertController(title: title, message: """
            The provided CSV file was \(reason). If the file was generated by this app, then \
            this is may be a software bug. If so, please report the issue - you can email me \
            at Settings -> About -> Contact.
            """, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

/*Import from a CSV file. Generate an export file first to see the data format. Book covers will be downloaded for rows with a Google Books ID. Duplicates and invalid entries will be skipped.  Note: Title and Author cells are mandatory. Authors should be separated by semicolons and be entered in the form: "Lastname, Firstnames". Subjects should be separated by semicolons.
"""*/
}

extension Import: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        confirmImport(fromFile: url)
    }
}

extension Import: UIAdaptivePresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}
