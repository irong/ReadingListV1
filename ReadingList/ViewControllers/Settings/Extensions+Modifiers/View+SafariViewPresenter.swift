import Foundation
import SwiftUI

struct SafariViewPresenterWrapper<Wrapped>: View where Wrapped: View {
    let wrapped: Wrapped
    let url: URL
    @State var presenting = false

    var body: some View {
        return wrapped
            .safariView(isPresented: $presenting) {
                SafariView(url: url)
            }
            .onTapGesture { presenting.toggle() }
    }
}

extension View {
    func presentingSafari(_ url: URL) -> some View {
        return SafariViewPresenterWrapper(wrapped: self, url: url)
    }
}
