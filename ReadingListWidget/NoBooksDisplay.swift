import SwiftUI

struct NoBooksDisplay: View {
    let urlManager = ProprietaryURLManager()

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("No Books")
            HStack(alignment: .center, spacing: 2) {
                Text(Image(systemName: "plus.circle.fill"))
                Text("Add New Book")
            }
            .foregroundColor(.blue)
            .actionLink(.addBookSearchOnline)
        }
    }
}
