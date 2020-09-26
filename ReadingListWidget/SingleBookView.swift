import Foundation
import SwiftUI
import WidgetKit

struct SingleBookView: View {
    let book: SharedBookData
    let entryDate: Date

    var daysRead: Int? {
        guard let daysBetween = book.startDate?.daysUntil(entryDate), daysBetween >= 0 else {
            return nil
        }
        return daysBetween
    }

    var daysReadText: String? {
        guard let daysRead = daysRead, daysRead > 0 else { return nil }
        return "\(daysRead) day\(daysRead == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .center) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading) {
                    Image(uiImage: book.coverUiImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 45, alignment: .leading)
                        .cornerRadius(6)
                    if book.percentageComplete == nil, let daysReadText = daysReadText {
                        Text(daysReadText)
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                            .padding(.leading, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .allowsTightening(true)
                    Text(book.authorDisplay)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            if let progress = book.percentageComplete {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressBar(currentProgress: CGFloat(progress) / 100)
                        .frame(height: 2)
                    HStack {
                        Text("\(progress)%")
                        Spacer()
                        if let daysReadText = daysReadText {
                            Text(daysReadText)
                        }
                    }
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                }.padding([.leading, .trailing], 4)
            }
        }
        .padding([.top, .bottom], 16)
        .padding([.leading, .trailing], 8)
        .offset(x: 0, y: book.percentageComplete == nil ? -8 : 0)
        .widgetURL(for: .viewBook(id: book.id))
    }

}

struct SingleBook_Previews: PreviewProvider {
    static let data: [SharedBookData] = {
        let dataPath = Bundle.main.url(forResource: "shared_book_data", withExtension: "json")!
        return try! JSONDecoder().decode([SharedBookData].self, from: Data(contentsOf: dataPath))
    }()

    static var previews: some View {
        Group {
            ForEach(data) {
                SingleBookView(book: $0, entryDate: Date())
                    .previewContext(WidgetPreviewContext(family: .systemSmall))
            }
        }.background(Color(.secondarySystemBackground))
    }
}
