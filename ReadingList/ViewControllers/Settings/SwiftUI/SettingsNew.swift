import SwiftUI

enum SettingsSelection {
    case about
    case general
    case tip
    case sort
    case importExport
}

struct SettingsNew: View {
    let writeReviewUrl = URL(string: "itms-apps://\(Settings.appStoreAddress)?action=write-review")!
    let showDetail: (SettingsSelection) -> Void
    @State var selectedRow: SettingsSelection? = .about

    func background(_ row: SettingsSelection) -> some View {
        if row != selectedRow { return Color.clear }
        return Color(.systemGray4)
    }
    
    func onCellSelect(_ selection: SettingsSelection) {
        showDetail(selection)
        selectedRow = selection
    }

    var body: some View {
        //NavigationView {
            Form {
                Section {
                    SettingsHeader()
                }.listRowBackground(Color(.groupTableViewBackground))
                Section {
                    SettingsCell("About", imageName: "info", color: .blue).onTapGesture {
                        onCellSelect(.about)
                    }.listRowBackground(background(.about))
                    SettingsCell("Rate", imageName: "star.fill", color: .orange)
                        .buttonWithTap {
                            UIApplication.shared.open(writeReviewUrl, options: [:])
                            selectedRow = nil
                        }
                    SettingsCell("Leave Tip", imageName: "heart.fill", color: .pink)
                        .onTapGesture {
                            onCellSelect(.tip)
                        }.listRowBackground(background(.tip))
                }
                Section {
                    SettingsCell("General", imageName: "gearshape.fill", color: .gray)
                        .onTapGesture {
                            onCellSelect(.general)
                        }.listRowBackground(background(.general))
                    SettingsCell("Sort", imageName: "chevron.up.chevron.down", color: .blue)
                        .onTapGesture {
                            onCellSelect(.sort)
                        }.listRowBackground(background(.sort))
                    SettingsCell("Import / Export", imageName: "doc.fill", color: .green).onTapGesture {
                        onCellSelect(.importExport)
                    }.listRowBackground(background(.importExport))
                }
            }
        //.navigationBarTitle("Settings", displayMode: .inline)
        //}.navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}

struct SettingsHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Image("AppIconOnWhiteRounded")
                .resizable()
                .frame(width: 80, height: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("Reading List").fontWeight(.semibold)
                    Text("v\(BuildInfo.thisBuild.versionAndConfiguration)").font(.system(size: 12))
                }
                Text("by Andrew Bennet").font(.footnote)
            }
        }
    }
}

struct SettingsNew_Previews: PreviewProvider {
    static var previews: some View {
        SettingsNew(showDetail: { _ in })
    }
}
