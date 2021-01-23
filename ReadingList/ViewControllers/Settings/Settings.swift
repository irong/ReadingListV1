import SwiftUI

struct Settings: View {
    static let appStoreAddress = "itunes.apple.com/gb/app/reading-list-book-tracker/id1217139955"
    static let feedbackEmailAddress = "feedback@readinglist.app"
    let writeReviewUrl = URL(string: "itms-apps://\(Settings.appStoreAddress)?action=write-review")!

    @EnvironmentObject var hostingSplitView: HostingSettingsSplitView
    @State var badgeOnBackupRow = AutoBackupManager.shared.cannotRunScheduledAutoBackups

    func background(_ row: SettingsSelection) -> some View {
        if row != hostingSplitView.selectedCell { return Color.clear }
        return Color(.systemGray4)
    }

    var backgroundColor: some View {
        Color(.systemGroupedBackground)
            .edgesIgnoringSafeArea([.leading, .trailing])
    }

    var header: some View {
        HStack {
            Spacer()
            if #available(iOS 14.0, *) {
                SettingsHeader().textCase(nil)
            } else {
                SettingsHeader()
            }
            Spacer()
        }.padding(.vertical, 20)
    }

    var body: some View {
        SwiftUI.List {
            Section(header: header) {
                SettingsCell(.about, title: "About", imageName: "info", color: .blue)
                IconCell("Rate", imageName: "star.fill", backgroundColor: .orange)
                    .onTapGesture {
                        UIApplication.shared.open(writeReviewUrl, options: [:])
                    }
                    .foregroundColor(Color(.label))
                SettingsCell(.tip, title: "Leave Tip", imageName: "heart.fill", color: .pink)
            }
            Section {
                SettingsCell(.general, title: "General", imageName: "gear", color: .gray)
                SettingsCell(.sort, title: "Sort", imageName: "chevron.up.chevron.down", color: .blue)
                SettingsCell(.importExport, title: "Import / Export", imageName: "doc.fill", color: .green)
                SettingsCell(.backup, title: "Backup & Restore", imageName: "icloud.fill", color: .icloudBlue, badge: badgeOnBackupRow)
                    .onReceive(NotificationCenter.default.publisher(for: .autoBackupEnabledOrDisabled)) { _ in
                        badgeOnBackupRow = AutoBackupManager.shared.cannotRunScheduledAutoBackups
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification)) { _ in
                        badgeOnBackupRow = AutoBackupManager.shared.cannotRunScheduledAutoBackups
                    }
            }
        }.listStyle(GroupedListStyle())
        .navigationBarTitle("Settings")
    }
}

extension Color {
    static let icloudBlue = Color(
        .sRGB,
        red: 62 / 255,
        green: 149 / 255,
        blue: 236 / 255,
        opacity: 1
    )
}

struct SettingsHeader: View {
    var version: String {
        "v\(BuildInfo.thisBuild.version)"
    }

    @State var isShowingDebugMenu = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("AppIconOnWhiteRounded")
                .resizable()
                .frame(width: 80, height: 80, alignment: .leading)
                .onLongPressGesture {
                    isShowingDebugMenu.toggle()
                }.sheet(isPresented: $isShowingDebugMenu) {
                    DebugSettings(isPresented: $isShowingDebugMenu)
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("Reading List")
                        .fontWeight(.semibold)
                        .font(.callout)
                    Text(version).font(.footnote)
                }.foregroundColor(Color(.label))
                Text("by Andrew Bennet")
                    .font(.footnote)
            }
        }
    }
}

struct SettingsCell: View {
    @EnvironmentObject var hostingSplitView: HostingSettingsSplitView
    var isSelected: Bool {
        hostingSplitView.selectedCell == cell
    }

    var selectedColor: Color {
        if hostingSplitView.isSplit {
            return Color(UIColor(named: "SplitViewCellSelection")!)
        } else {
            return .clear
        }
    }

    var cellBackground: Color {
        isSelected ? selectedColor : Color.clear
    }

    var cellLabelColor: Color {
        isSelected && hostingSplitView.isSplit ? .white : Color(.label)
    }

    let cell: SettingsSelection
    let title: String
    let imageName: String
    let imageBackgroundColor: Color
    let badge: Bool

    init(_ cell: SettingsSelection, title: String, imageName: String, color: Color, badge: Bool = false) {
        self.cell = cell
        self.title = title
        self.imageName = imageName
        self.imageBackgroundColor = color
        self.badge = badge
    }

    var body: some View {
        IconCell(
            title,
            imageName: imageName,
            backgroundColor: imageBackgroundColor,
            withChevron: !hostingSplitView.isSplit,
            withBadge: badge ? "1" : nil,
            textForegroundColor: cellLabelColor
        )
        .onTapGesture {
            hostingSplitView.selectedCell = cell
        }
        .listRowBackground(cellBackground.edgesIgnoringSafeArea([.horizontal]))
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        Settings().environmentObject(HostingSettingsSplitView())
    }
}
