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
    private let selectFileCellIndex = IndexPath(row: 0, section: 3)

    @Persisted("importFormat", defaultValue: .readingList)
    private var importFormat: CSVImportFormat {
        didSet {
            importFormatDescription.text = importFormat.description
        }
    }

    @Persisted(encodedDataKey: "importSettings", defaultValue: .init())
    var importSettings: BookCSVImportSettings

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
            if let label = cell.contentView.subviews.compactMap({ $0 as? UILabel }).first {
                label.textColor = indexPath == selectFileCellIndex ? .systemBlue : GeneralSettings.theme.titleTextColor
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath == IndexPath(row: 0, section: 0) {
            let alert = UIAlertController(title: "Select Import Format", message: nil, preferredStyle: .actionSheet)
            alert.addActions(CSVImportFormat.allCases.map { format in
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
        } else if indexPath == selectFileCellIndex {
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

    func presentDocumentPicker(presentingIndexPath: IndexPath) {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.comma-separated-values-text"], in: .import)
        documentPicker.delegate = self
        documentPicker.popoverPresentationController?.setSourceCell(atIndexPath: presentingIndexPath, inTable: tableView, arrowDirections: .up)
        present(documentPicker, animated: true)
    }

    func confirmImport(fromFile url: URL) {
        var message = "Are you sure you want to import books from this file?"
        if importSettings.overwriteExistingBooks {
            message += " This will overwrite any existing books which have a matching ISBN"
            if importFormat == .readingList {
                message += " or Google Books ID."
            } else {
                message += "."
            }
        }
        let alert = UIAlertController(title: "Confirm \(importFormat.description) Import", message: message, preferredStyle: .alert)
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
        let alert = UIAlertController(title: error.title, message: """
            The provided CSV file was \(error.reason). Please ensure that the provided file meets the
            requirements of the \(importFormat) CSV format.
            """, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
}

extension CSVImportError {
    var title: String {
        switch self {
        case .invalidCsv: return "Invalid CSV File"
        case .missingHeaders: return "Missing CSV Columns"
        }
    }

    var reason: String {
        switch self {
        case .invalidCsv: return "not valid"
        case .missingHeaders: return "missing required columns"
        }
    }
}

extension Import: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        confirmImport(fromFile: url)
    }
}
