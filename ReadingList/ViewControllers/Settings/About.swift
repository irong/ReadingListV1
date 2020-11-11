import Foundation
import UIKit
import MessageUI
import SafariServices

final class About: UITableViewController {

    let thisVersionChangeList = ChangeListProvider().thisVersionChangeList()
    let changeListRowIndex = 6

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let rowCount = super.tableView(tableView, numberOfRowsInSection: section)
        // We hide this (bottom) cell if we aren't showing a change list
        if thisVersionChangeList == nil {
            return rowCount - 1
        } else {
            return rowCount
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        if indexPath.section == 0 && indexPath.row == changeListRowIndex && thisVersionChangeList == nil {
            cell.isHidden = true
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { assertionFailure("Unexpected footer view type"); return }
        guard let textLabel = footer.textLabel else { assertionFailure("Missing text label"); return }
        textLabel.textAlignment = .center
        textLabel.font = .systemFont(ofSize: 11.0)
        textLabel.text = "v\(BuildInfo.thisBuild.version) (\(BuildInfo.thisBuild.buildNumber))"
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else { return }
        switch indexPath.row {
        case 0: present(SFSafariViewController(url: URL(string: "https://www.readinglist.app")!), animated: true)
        case 1: share(indexPath)
        case 2: present(SFSafariViewController(url: URL(string: "https://twitter.com/ReadingListApp")!), animated: true)
        case 3: contact(indexPath)
        case 4: present(SFSafariViewController(url: URL(string: "https://github.com/AndrewBennet/readinglist")!), animated: true)
        case changeListRowIndex:
            if let thisVersionChangeList = thisVersionChangeList {
                present(thisVersionChangeList, animated: true)
            }
        default: return
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func share(_ indexPath: IndexPath) {
        let appStoreUrl = URL(string: "https://\(Settings.appStoreAddress)")!
        let activityViewController = UIActivityViewController(activityItems: [appStoreUrl], applicationActivities: nil)
        activityViewController.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
        present(activityViewController, animated: true)
    }

    private func contact(_ indexPath: IndexPath) {
        let canSendEmail = MFMailComposeViewController.canSendMail()

        let controller = UIAlertController(title: "", message: """
            Hi there 👋

            To suggest features or report bugs, please email me. I try my best to \
            reply to every email I receive, but this app is a one-person project, so \
            please be patient if it takes a little time for my reply!

            If you do have a specific question, I would suggest first looking on the FAQ \
            in case your answer is there.
            """, preferredStyle: .alert)
        if canSendEmail {
            controller.addAction(UIAlertAction(title: "Email", style: .default) { _ in
                self.presentContactMailComposeWindow()
            })
        } else {
            controller.addAction(UIAlertAction(title: "Copy Email Address", style: .default) { _ in
                UIPasteboard.general.string = "feedback@readinglist.app"
            })
        }
        controller.addAction(UIAlertAction(title: "Open FAQ", style: .default) { _ in
            self.present(SFSafariViewController(url: URL(string: "https://www.readinglist.app/faqs/")!), animated: true)
        })
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(controller, animated: true)
    }

    private func presentContactMailComposeWindow() {
        let mailComposer = MFMailComposeViewController()
        mailComposer.mailComposeDelegate = self
        mailComposer.setToRecipients(["Reading List Developer <\(Settings.feedbackEmailAddress)>"])
        mailComposer.setSubject("Reading List Feedback")
        let messageBody = """
        Your Message Here:




        Extra Info:
        App Version: \(BuildInfo.thisBuild.fullDescription)
        iOS Version: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.modelName)
        """
        mailComposer.setMessageBody(messageBody, isHTML: false)
        present(mailComposer, animated: true)
    }
}

extension About: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true)
    }
}
