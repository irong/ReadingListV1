import Foundation
import SwiftUI

struct BookDetails: View {
    let bookData: SharedBookData

    var body: some View {
        VStack(alignment: .center) {
            Image(uiImage: bookData.coverUiImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 80)
                .cornerRadius(4, corners: .allCorners)
            Text(bookData.title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(bookData.percentageComplete != nil ? 2 : 4)
                .fixedSize(horizontal: false, vertical: true)
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
            return UIImage(named: "CoverPlaceholder")!
        }
    }
}
