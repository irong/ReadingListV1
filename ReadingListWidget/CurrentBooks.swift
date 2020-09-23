import Foundation
import SwiftUI

struct CurrentBooks: View {
    let books: [SharedBookData]

    private let urlManager = ProprietaryURLManager()
    private let booksPerRow = 4

    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(books.prefix(booksPerRow)) { book in
                        // We need to pass in the desired image height so that BookDetails doesn't need to use
                        // a GeometryReader, which gobbles up all available height.
                        BookDetails(bookData: book, imageHeight: geometry.size.height / 1.7)
                            // Put the padding here rather than spacing in the HStack, so we can correctly set the frame width to be
                            // the correct proportion of the total width.
                            .padding([.leading, .trailing], 8)
                            .frame(
                                width: (geometry.size.width / CGFloat(booksPerRow)).rounded(.down),
                                alignment: .top
                            )
                            .actionLink(.viewBook(id: book.id))
                    }
                }
            }
            // Expand the VStack to be full height and width of the frame, so that the books HStack
            // sits in the vertical center.
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            // Push the full height VStack slightly up - it looks a bit nicer
            .offset(x: 0, y: -4)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color(UIColor.secondarySystemBackground))
    }
}
