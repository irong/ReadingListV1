import SwiftUI
import UIKit
import WhatsNewKit
import SafariServices

extension Color {
    static let twitterBlue = Color(
        .sRGB,
        red: 76 / 255,
        green: 160 / 255,
        blue: 235 / 255,
        opacity: 1
    )

    static let paleEmailBlue = Color(
        .sRGB,
        red: 94 / 255,
        green: 191 / 255,
        blue: 244 / 255,
        opacity: 1
    )
}

struct AboutFooter: View {
    var body: some View {
        Text("v\(BuildInfo.thisBuild.version.description) (\(BuildInfo.thisBuild.buildNumber))")
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.caption)
    }
}

struct TwitterIcon: View {
    var body: some View {
        SettingsIcon(color: .twitterBlue) {
            Image("twitter")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.white)
                .frame(width: 18, height: 18, alignment: .center)
        }
    }
}

struct GitHubIcon: View {
    var body: some View {
        SettingsIcon(color: .black) {
            Image("github")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.white)
                .frame(width: 22, height: 22, alignment: .center)
        }
    }
}

struct AboutNew: View {

    let changeListProvider = ChangeListProvider()

    var body: some View {
        Form {
            Section(footer: AboutFooter()) {
                SettingsCell("Website", imageName: "house.fill", color: .blue, withChevron: true)
                    .presentingSafari(URL(string: "https://readinglist.app")!)
                SettingsCell("Share", imageName: "paperplane.fill", color: .orange)
                    .modal(ActivityView(activityItems: [URL(string: "https://\(Settings.appStoreAddress)")!]))
                SettingsCell("Twitter", image: TwitterIcon(), withChevron: true)
                    .presentingSafari(URL(string: "https://twitter.com/ReadingListApp")!)
                SettingsCell("Email", imageName: "envelope.fill", color: .paleEmailBlue)
                SettingsCell("Source Code", image: GitHubIcon(), withChevron: true)
                    .presentingSafari(URL(string: "https://github.com/AndrewBennet/ReadingList")!)
                SettingsCell("Attributions", imageName: "heart.fill", color: .green)
                    .navigating(to: AttributionsNew())
                if changeListProvider.thisVersionChangeList() != nil {
                    SettingsCell("Recent Changes", imageName: "wrench.fill", color: .blue, withChevron: true)
                        .modal(ChangeListWrapper())
                }
            }
        }.navigationBarTitle("About")
    }
}

extension View {
    func navigating<Destination>(to destination: Destination) -> some View where Destination: View {
        return NavigationLink(
            destination: destination,
            label: {
                self
            }
        )
    }
}

struct ModalPresenter<Wrapped, Modal>: View where Wrapped: View, Modal: View {
    @State var isPresented = false
    var wrapped: Wrapped
    var modal: Modal

    var body: some View {
        return wrapped.sheet(isPresented: $isPresented) {
            modal
        }.buttonWithTap {
            isPresented.toggle()
        }
    }
}

struct ButtonTapWrapper<Wrapped>: View where Wrapped: View {
    let wrapped: Wrapped
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            wrapped
        }).buttonStyle(PlainButtonStyle())
    }
}

extension View {
    func buttonWithTap(_ action: @escaping () -> Void) -> some View {
        return ButtonTapWrapper(wrapped: self, action: action)
    }
}

extension View {
    func modal<Modal>(_ modal: Modal) -> some View where Modal: View {
        return ModalPresenter(wrapped: self, modal: modal)
    }
}

struct SafariPresenter<Wrapped>: View where Wrapped: View {
    let wrapped: Wrapped
    let url: URL
    @State var presenting = false

    var body: some View {
        return wrapped
            .safariView(isPresented: $presenting) {
                SafariView(url: url)
            }
            .buttonWithTap { presenting.toggle() }
    }
}

extension View {
    func presentingSafari(_ url: URL) -> some View {
        return SafariPresenter(wrapped: self, url: url)
    }
}

struct AboutNew_Previews: PreviewProvider {
    static var previews: some View {
        AboutNew()
    }
}

struct ChangeListWrapper: UIViewControllerRepresentable {
    typealias UIViewControllerType = WhatsNewViewController
    let changeListProvider = ChangeListProvider()

    func makeUIViewController(context: Context) -> WhatsNewViewController {
        return changeListProvider.thisVersionChangeList()!
    }

    func updateUIViewController(_ uiViewController: WhatsNewViewController, context: Context) { }
}

struct ActivityView: UIViewControllerRepresentable {

    var activityItems: [Any]
    var applicationActivities: [UIActivity]?

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityView>) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityView>) {}
}
