import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), books: SharedBookData.sharedBooks)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), books: SharedBookData.sharedBooks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entries = [SimpleEntry(date: Date(), books: SharedBookData.sharedBooks)]
        let timeline = Timeline(entries: entries, policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let books: [SharedBookData]
}

struct ReadingListWidgetEntryView: View {
    var entry: Provider.Entry
    let urlManager = ProprietaryURLManager()
    
    var body: some View {
        GeometryReader { geometry in
        HStack {
            if entry.books.isEmpty {
                Text("No books")
            } else {
                ForEach(entry.books) { book in
                    Link(destination: urlManager.getURL(from: .viewBook(id: book.id))) {
                        
                        BookView(bookData: book)
                            .frame(width: (geometry.size.width / 4).rounded(.down) - 6,
                                   height: (geometry.size.height - 6),
                                   alignment: .top)
                        }
                    }
                }
            }
        }
    }
}

struct BookView: View {
    let bookData: SharedBookData
    var body: some View {
        VStack {
            if let coverData = bookData.coverImage {
                Image(uiImage: UIImage(data: coverData)!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 53, height: 80)
            } else {
                Image(uiImage: UIImage(named: "CoverPlaceholder")!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 53, height: 80)
            }
            Text(bookData.title).font(.caption)
            Text(bookData.authorDisplay)
                .font(.caption2)
                .foregroundColor(.secondary)
        }//.padding()
        
        .background(Color(.systemGroupedBackground))
        .cornerRadius(8, corners: .allCorners)
    }
}

@main
struct ReadingListWidget: Widget {
    let kind: String = "ReadingListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ReadingListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
        .supportedFamilies([.systemMedium])
    }
}

struct ReadingListWidget_Previews: PreviewProvider {
    static var previews: some View {
        ReadingListWidgetEntryView(entry: SimpleEntry(date: Date(), books: []))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
