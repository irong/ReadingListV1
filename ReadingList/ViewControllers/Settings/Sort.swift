import Foundation
import SwiftUI

struct Sort: View {
    @State var addBooksToTop = GeneralSettings.addBooksToTopOfCustom {
        didSet {
            GeneralSettings.addBooksToTopOfCustom = addBooksToTop
        }
    }

    @EnvironmentObject var hostingSplitView: HostingSplitView
    
    var body: some View {
        SwiftUI.List {
            Section(
                header: HeaderText("Sort Options", inset: hostingSplitView.isSplit),
                footer: FooterText("""
                    Configure whether newly added books get added to the top or the bottom of the \
                    reading list when Custom ordering is used.
                    """, inset: hostingSplitView.isSplit
                )
            ) {
                Toggle(isOn: $addBooksToTop) {
                    Text("Add Books to Top")
                }
            }
        }.possiblyInsetGroupedListStyle(inset: hostingSplitView.isSplit)
    }
}
