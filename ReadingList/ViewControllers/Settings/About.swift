import SwiftUI
import UIKit
import WhatsNewKit
import SafariServices
import MessageUI

struct About: View {
    let changeListProvider = ChangeListProvider()
    @State var isShowingMailAlert = false
    @State var isShowingMailView = false
    @State var isShowingFaq = false
    @EnvironmentObject var hostingSplitView: HostingSplitView

    var body: some View {
        SwiftUI.List {
            Section(footer: AboutFooter()) {
                IconCell("Website",
                         imageName: "house.fill",
                         backgroundColor: .blue,
                         withChevron: true
                ).presentingSafari(URL(string: "https://readinglist.app")!)

                IconCell("Share",
                         imageName: "paperplane.fill",
                         backgroundColor: .orange
                ).modal(ActivityView(activityItems: [URL(string: "https://\(Settings.appStoreAddress)")!], applicationActivities: nil))

                IconCell("Twitter",
                         image: TwitterIcon(),
                         withChevron: true
                ).presentingSafari(URL(string: "https://twitter.com/ReadingListApp")!)

                IconCell("Email",
                         imageName: "envelope.fill",
                         backgroundColor: .paleEmailBlue
                ).onTapGesture {
                    isShowingMailAlert.toggle()
                }.actionSheet(isPresented: $isShowingMailAlert) {
                    mailAlert
                }.sheet(isPresented: $isShowingMailView) {
                    mailView
                }

                IconCell("Source Code",
                         image: GitHubIcon(),
                         withChevron: true
                ).presentingSafari(URL(string: "https://github.com/AndrewBennet/ReadingList")!)

                IconCell("Attributions",
                         imageName: "heart.fill",
                         backgroundColor: .green
                ).navigating(to: Attributions())

                if changeListProvider.thisVersionChangeList() != nil {
                    IconCell("Recent Changes",
                             imageName: "wrench.fill",
                             backgroundColor: .blue,
                             withChevron: true
                    ).modal(ChangeListWrapper())
                }
            }
        }
        .possiblyInsetGroupedListStyle(inset: hostingSplitView.isSplit)
        .navigationBarTitle("About")
    }

    var mailAlert: ActionSheet {
        let emailButton: ActionSheet.Button
        if MFMailComposeViewController.canSendMail() {
            emailButton = .default(Text("Email"), action: {
                isShowingMailView = true
            })
        } else {
            emailButton = .default(Text("Copy Email Address"), action: {
                UIPasteboard.general.string = "feedback@readinglist.app"
            })
        }
        return ActionSheet(
            title: Text(""),
            message: Text("""
         Hi there!

         To suggest features or report bugs, please email me. I try my best to \
         reply to every email I receive, but this app is a one-person project, so \
         please be patient if it takes a little time for my reply!

         If you do have a specific question, I would suggest first looking on the FAQ \
         in case your answer is there.
         """),
            buttons: [
            emailButton,
            .default(Text("Open FAQ"), action: {
                isShowingFaq = true
            }),
            .cancel(Text("Dismiss"), action: {})
            ]
        )
    }

    var mailView: MailView {
        MailView(
            isShowing: $isShowingMailView,
            receipients: [
                "Reading List Developer <\(Settings.feedbackEmailAddress)>"
            ],
            messageBody: """
            Your Message Here:




            Extra Info:
            App Version: \(BuildInfo.thisBuild.fullDescription)
            iOS Version: \(UIDevice.current.systemVersion)
            Device: \(UIDevice.current.modelName)
            """,
            subject: "Reading List Feedback"
        )
    }
}

struct AboutFooter: View {
    var body: some View {
        Text("v\(BuildInfo.thisBuild.version.description) (\(BuildInfo.thisBuild.buildNumber))")
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.caption)
    }
}

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

fileprivate extension Image {
    func iconTemplate() -> some View {
        self.resizable()
            .renderingMode(.template)
            .foregroundColor(.white)
    }
}

struct TwitterIcon: View {
    var body: some View {
        SettingsIcon(color: .twitterBlue) {
            Image("twitter")
                .iconTemplate()
                .frame(width: 18, height: 18, alignment: .center)
        }
    }
}

struct GitHubIcon: View {
    var body: some View {
        SettingsIcon(color: .black) {
            Image("github")
                .iconTemplate()
                .frame(width: 22, height: 22, alignment: .center)
        }
    }
}

struct AboutNew_Previews: PreviewProvider {
    static var previews: some View {
        About()
    }
}
