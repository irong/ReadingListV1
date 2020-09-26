import SwiftUI
import WidgetKit

struct NoBooksView: View {
    let urlManager = ProprietaryURLManager()

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("No Current Books")
                .font(.system(.headline))
            HStack(alignment: .center, spacing: 2) {
                Text(Image(systemName: "plus.circle.fill"))
                    .offset(x: 0, y: 1)
                Text("Add Book")
                    .font(.system(.headline))
            }
            .foregroundColor(.blue)
            .actionLink(.addBookSearchOnline)
        }
    }
}

struct NoBooksView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NoBooksView()
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            NoBooksView()
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
