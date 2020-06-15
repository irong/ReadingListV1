import Foundation
import ReadingList_Foundation
import WhatsNewKit

struct ChangeListProvider {
    let changeLog = [
        Version(major: 1, minor: 13, patch: 0): [
            WhatsNew.Item(
                title: "Bulk Scan",
                subtitle: "Scan multiple barcodes in one session",
                image: UIImage(largeSystemImageNamed: "barcode", pointSize: 40)
            ),
            WhatsNew.Item(
                title: "Import from GoodReads",
                subtitle: "CSV Import can now be performed from a GoodReads file",
                image: UIImage(largeSystemImageNamed: "arrow.up.doc.fill", pointSize: 40)
            ),
            WhatsNew.Item(
                title: "Improvements and Fixes",
                subtitle: "Various improvements and fixes",
                image: UIImage(largeSystemImageNamed: "ant.fill", pointSize: 40)
            )
        ]
    ]

    func thisVersionChangeList() -> UIViewController? {
        if let items = changeLog[BuildInfo.thisBuild.version] {
            return whatsNewViewController(for: items)
        }
        // Get the versions which match this major and minor version, and find the largest patch-number version of that (if any)
        guard let matchingMajorMinorChangeLog = changeLog.keys.filter({
            $0.major == BuildInfo.thisBuild.version.major && $0.minor == BuildInfo.thisBuild.version.minor
        }).max() else { return nil }
        return whatsNewViewController(for: changeLog[matchingMajorMinorChangeLog]!)
    }

    func changeListController(after version: Version) -> UIViewController? {
        // Reverse before distincting, so we keep the last occurance of any duplicate, rather than the first
        let items = changeLog.filter { $0.key > version }.map { $0.value }.reduce([], +).reversed().distinct().reversed()
        if items.isEmpty {
            return nil
        }
        return whatsNewViewController(for: Array(items))
    }

    private func whatsNewViewController(for items: [WhatsNew.Item]) -> WhatsNewViewController {
        let coloredTitlePortion = "Reading List"
        let title = "What's New in \(coloredTitlePortion)"
        let whatsNew = WhatsNew(title: title, items: items)

        var configuration = WhatsNewViewController.Configuration()
        configuration.itemsView.imageSize = .original
        if let startIndex = title.startIndex(ofFirstSubstring: coloredTitlePortion) {
            configuration.titleView.secondaryColor = .init(startIndex: startIndex, length: coloredTitlePortion.count, color: .systemBlue)
        } else {
            assertionFailure("Could not find title substring")
        }

        return WhatsNewViewController(whatsNew: whatsNew, configuration: configuration)
    }
}
