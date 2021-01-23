import Foundation
import SwiftUI

class SortSettings: ObservableObject {
    @Published var addBooksToTop: Bool = GeneralSettings.addBooksToTopOfCustom {
        didSet {
            GeneralSettings.addBooksToTopOfCustom = addBooksToTop
        }
    }
}

struct Sort: View {
    @EnvironmentObject var hostingSplitView: HostingSettingsSplitView
    @ObservedObject var settings = SortSettings()

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
                Toggle(isOn: $settings.addBooksToTop) {
                    Text("Add Books to Top")
                }
            }
        }.possiblyInsetGroupedListStyle(inset: hostingSplitView.isSplit)
        .navigationBarTitle("Sort")
    }
}
