import Foundation
import SwiftUI
import WidgetKit

struct SingleBookOrAddBook: View {
    let book: SharedBookData?

    var body: some View {
        if let book = book {
            SingleBookView(book: book)
        } else {
            NoBooksDisplay().widgetURL(for: .addBookSearchOnline)
        }
    }
}

struct SingleBookView: View {
    let book: SharedBookData

    var body: some View {
        GeometryReader { geometryProxy in
            VStack(alignment: .center) {
                HStack(alignment: .top, spacing: 8) {
                    Image(uiImage: book.coverUiImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 2 * geometryProxy.size.width / 5, alignment: .leading)
                        .cornerRadius(4)
                    VStack(alignment: .leading) {
                        Text(book.title)
                            .font(.system(.body))
                            .fontWeight(.medium)
                        Text(book.authorDisplay)
                            .font(.system(.caption))
                        if let progress = book.percentageComplete {
                            VStack(alignment: .center, spacing: 2) {
                                ProgressBar(currentProgress: CGFloat(progress) / 100)
                                    .frame(width: geometryProxy.size.width / 3)
                                    .frame(height: 2)
                                Text("\(progress)%")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption2))
                            }
                        }
                    }
                }.padding([.leading, .trailing], 4)
            }.frame(
                width: geometryProxy.size.width,
                height: geometryProxy.size.height,
                alignment: .center
            )
            .offset(x: 0, y: -4)
            .background(Color(.secondarySystemBackground))
        }
        .widgetURL(for: .viewBook(id: book.id))
    }

}

struct SingleBook_Previews: PreviewProvider {
    static let data: SharedBookData? = {
        let dataPath = Bundle.main.url(forResource: "shared_book_data", withExtension: "json")!
        return try! JSONDecoder().decode([SharedBookData].self, from: Data(contentsOf: dataPath)).first
    }()

    static var previews: some View {
        Group {
            SingleBookOrAddBook(book: nil)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SingleBookOrAddBook(book: data)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
