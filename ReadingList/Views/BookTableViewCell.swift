import Foundation
import UIKit

class BookTableViewCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var authorsLabel: UILabel!
    @IBOutlet private weak var bookCover: UIImageView!
    @IBOutlet private weak var readTimeLabel: UILabel!
    @IBOutlet private weak var readingProgress: UIProgressView!
    @IBOutlet private weak var readingProgressLabel: UILabel!

    private var coverImageRequest: URLSessionDataTask?

    func resetUI() {
        titleLabel.text = nil
        authorsLabel.text = nil
        readTimeLabel.text = nil
        bookCover.image = nil
        readingProgress.isHidden = true
        readingProgressLabel.text = nil
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        initialise(withTheme: UserDefaults.standard[.theme])
        resetUI()
    }

    func initialise(withTheme theme: Theme) {
        defaultInitialise(withTheme: theme)
        titleLabel.textColor = theme.titleTextColor
        authorsLabel.textColor = theme.subtitleTextColor
        readTimeLabel?.textColor = theme.subtitleTextColor
        readingProgressLabel.textColor = theme.subtitleTextColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        // Cancel any pending cover data request task
        coverImageRequest?.cancel()
        coverImageRequest = nil

        resetUI()
    }

    func configureFrom(_ book: Book, includeReadDates: Bool = true) {
        titleLabel.text = book.title
        authorsLabel.text = book.authors.fullNames
        bookCover.image = UIImage(optionalData: book.coverImage) ?? #imageLiteral(resourceName: "CoverPlaceholder")
        if includeReadDates {
            switch book.readState {
            case .reading: readTimeLabel.text = book.startedReading!.toPrettyString()
            case .finished: readTimeLabel.text = book.finishedReading!.toPrettyString()
            default: readTimeLabel.text = nil
            }

            // Configure the reading progress display
            if let currentPage = book.currentPage, let pageCount = book.pageCount, currentPage > 0 {
                let progress = Float(currentPage) / Float(pageCount)
                let progressText = currentPage > pageCount ? "100%" : "\(100 * (currentPage / pageCount))%"
                configureReadingProgress(text: progressText, progress: progress)
            }
        }

        #if DEBUG
            if UserDefaults.standard[.showSortNumber] {
                titleLabel.text = "(\(book.sort)) \(book.title)"
            }
        #endif
    }

    private func configureReadingProgress(text: String?, progress: Float) {
        readingProgressLabel.text = text
        readingProgress.isHidden = false
        readingProgress.progress = progress
    }

    func configureFrom(_ searchResult: SearchResult) {
        titleLabel.text = searchResult.title
        authorsLabel.text = searchResult.authors.fullNames

        guard let coverURL = searchResult.thumbnailCoverUrl else { bookCover.image = #imageLiteral(resourceName: "CoverPlaceholder"); return }
        coverImageRequest = URLSession.shared.startedDataTask(with: coverURL) { [weak self] data, _, _ in
            guard let cell = self else { return }
            DispatchQueue.main.async {
                // Cancellations appear to be reported as errors. Ideally we would detect non-cancellation
                // errors (e.g. 404), and show the placeholder in those cases. For now, just make the image blank.
                cell.bookCover.image = UIImage(optionalData: data)
            }
        }
    }
}
