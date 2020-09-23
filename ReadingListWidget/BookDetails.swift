import Foundation
import SwiftUI

struct BookDetails: View {
    let bookData: SharedBookData
    let imageHeight: CGFloat

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(uiImage: bookData.coverUiImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: imageHeight)
                .cornerRadius(4, corners: .allCorners)
            Text(bookData.title)
                .font(.system(.caption2))
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .layoutPriority(-1) // Allow the text to be compressed in favour of the image / progress view.
            if let percentage = bookData.percentageComplete {
                ProgressDisplay(progressPercentage: percentage)
                    .actionLink(.editBookReadLog(id: bookData.id))
            }
        }
    }
}

extension SharedBookData {
    func coverUiImage() -> UIImage {
        if let coverData = coverImage, let uiImage = UIImage(data: coverData) {
            return uiImage
        } else {
            return UIImage(named: "CoverPlaceholder_White")!
        }
    }
}
