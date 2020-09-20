import Foundation
import SwiftUI

struct CurrentBooks: View {
    let urlManager = ProprietaryURLManager()
    let books: [SharedBookData]
    let maxBookCount = 4
    private let leadingTrailingPadding: CGFloat = 2
    private let topBottomPadding: CGFloat = 12

    func desiredWidth(_ geometryProxy: GeometryProxy) -> CGFloat {
        (geometryProxy.size.width / CGFloat(maxBookCount)).rounded(.down) - leadingTrailingPadding * 2
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(books[0..<maxBookCount]) { book in
                    BookDetails(bookData: book)
                        .frame(
                            width: desiredWidth(geometry),
                            height: geometry.size.height - topBottomPadding * 2,
                            alignment: .top
                        )
                        .padding([.leading, .trailing], leadingTrailingPadding)
                        .padding([.top, .bottom], topBottomPadding)
                        .actionLink(.viewBook(id: book.id))
                }
            }
        }
    }
}
