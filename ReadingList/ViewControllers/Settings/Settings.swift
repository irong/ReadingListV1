import SwiftUI

enum SettingsSelection {
    case about
    case general
    case tip
    case sort
    case importExport
    case backup
}

struct Settings: View {
    static let appStoreAddress = "itunes.apple.com/gb/app/reading-list-book-tracker/id1217139955"
    static let feedbackEmailAddress = "feedback@readinglist.app"
    let writeReviewUrl = URL(string: "itms-apps://\(Settings.appStoreAddress)?action=write-review")!
    
    @EnvironmentObject var hostingSplitView: HostingSplitView
    let showDetail: (SettingsSelection) -> Void

    @State var selectedRow: SettingsSelection? = .about
    @State var badgeOnBackupRow = AutoBackupManager.shared.cannotRunScheduledAutoBackups

    func background(_ row: SettingsSelection) -> some View {
        if row != selectedRow { return Color.clear }
        return Color(.systemGray4)
    }

    func onCellSelect(_ selection: SettingsSelection) {
        showDetail(selection)
        selectedRow = selection
    }

    var backgroundColor: some View {
        Color(.systemGroupedBackground)
            .edgesIgnoringSafeArea([.leading, .trailing])
    }
    
    var selectedColor: Color {
        if hostingSplitView.isSplit {
            return Color(UIColor(named: "SplitViewCellSelection")!)
        } else {
            return .clear
        }
    }
    
    func cell(_ cell: SettingsSelection, title: String, imageName: String, color: Color, badge: Bool = false) -> some View {
        let isSelected = selectedRow == cell
        let cellBackground = isSelected ? selectedColor : Color.clear
        return IconCell(
            title,
            imageName: imageName,
            backgroundColor: color,
            withChevron: !hostingSplitView.isSplit,
            withBadge: badge ? "1" : nil
        )
        .onTapGesture {
            onCellSelect(cell)
        }
        .foregroundColor(isSelected && hostingSplitView.isSplit ? .white : Color(.label))
        .listRowBackground(cellBackground.edgesIgnoringSafeArea([.horizontal]))
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
                cell(.about, title: "About", imageName: "info", color: .blue)
                IconCell("Rate", imageName: "star.fill", backgroundColor: .orange)
                    .onTapGesture {
                        UIApplication.shared.open(writeReviewUrl, options: [:])
                        selectedRow = nil
                    }
                    .foregroundColor(Color(.label))
                cell(.tip, title: "Leave Tip", imageName: "heart.fill", color: .pink)
            }
            Section {
                cell(.general, title: "General", imageName: "gear", color: .gray)
                cell(.sort, title: "Sort", imageName: "chevron.up.chevron.down", color: .blue)
                cell(.importExport, title: "Import / Export", imageName: "doc.fill", color: .green)
                cell(.backup, title: "Backup & Restore", imageName: "icloud.fill", color: .blue, badge: badgeOnBackupRow)
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

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        Settings { _ in }.environmentObject(HostingSplitView())
    }
}
