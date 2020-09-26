#if DEBUG

import Foundation
import Eureka
import SVProgressHUD

final class DebugForm: FormViewController {

    @objc func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    override func viewDidLoad() {
        if #available(iOS 13.0, *) {
            initialiseInsetGroupedTable()
        }

        super.viewDidLoad()

        navigationItem.title = "Debug"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Dismiss", style: .plain, target: self, action: #selector(dismissSelf))

        form +++ Section(header: "Test data", footer: "Import a set of data for both testing and screenshots")
            <<< ButtonRow {
                $0.title = "Import Test Data"
                $0.onCellSelection { _, _ in
                    SVProgressHUD.show(withStatus: "Loading Data...")
                    Debug.loadData(downloadImages: true) {
                        SVProgressHUD.dismiss()
                    }
                }
            }
            <<< ButtonRow {
                $0.title = "Export Shared Data"
                $0.onCellSelection { [weak self] cell, _ in
                    let encoded = try! JSONEncoder().encode(SharedBookData.sharedBooks)
                    let temporaryFilePath = URL.temporary(fileWithName: "shared_book_data.json")
                    try! encoded.write(to: temporaryFilePath)
                    let activityViewController = UIActivityViewController(activityItems: [temporaryFilePath], applicationActivities: [])
                    if let popover = activityViewController.popoverPresentationController {
                        popover.sourceView = cell
                        popover.sourceRect = cell.frame
                    }
                    self?.present(activityViewController, animated: true, completion: nil)
                }
            }

        +++ Section("Debug Controls")
            <<< SwitchRow {
                $0.title = "Show sort number"
                $0.value = Debug.showSortNumber
                $0.onChange {
                    Debug.showSortNumber = $0.value ?? false
                }
            }

        +++ Section("Error reporting")
            <<< ButtonRow {
                $0.title = "Crash"
                $0.cellUpdate { cell, _ in
                    cell.textLabel?.textColor = .red
                }
                $0.onCellSelection { _, _ in
                    fatalError("Test Crash")
                }
            }

        monitorThemeSetting()
    }
}

#endif
