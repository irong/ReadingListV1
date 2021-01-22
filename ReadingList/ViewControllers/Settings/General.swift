import SwiftUI
import ReadingList_Foundation

struct General: View {

    @State var expandedDescriptions = GeneralSettings.showExpandedDescription {
        didSet { GeneralSettings.showExpandedDescription = expandedDescriptions }
    }
    @State var progressType = GeneralSettings.defaultProgressType {
        didSet { GeneralSettings.defaultProgressType = progressType }
    }
    @State var prepopulateLastLanguageSelection = GeneralSettings.prepopulateLastLanguageSelection {
        didSet {
            GeneralSettings.prepopulateLastLanguageSelection = prepopulateLastLanguageSelection
            if !prepopulateLastLanguageSelection { LightweightDataStore.lastSelectedLanguage = nil }
        }
    }
    @State var sendCrashReports = UserEngagement.sendCrashReports {
        didSet { UserEngagement.sendCrashReports = sendCrashReports }
    }
    @State var sendAnalytics = UserEngagement.sendAnalytics {
        didSet { UserEngagement.sendAnalytics = sendAnalytics }
    }
    @State var restrictSearchResultsTo: LanguageSelection = {
        if let languageRestriction = GeneralSettings.searchLanguageRestriction {
            return .some(languageRestriction)
        } else {
            return LanguageSelection.none
        }
    }() {
        didSet {
            if case .some(let selection) = restrictSearchResultsTo {
                GeneralSettings.searchLanguageRestriction = selection
            } else {
                GeneralSettings.searchLanguageRestriction = .none
            }
        }
    }

    @State var crashReportsAlertDisplated = false
    @State var analyticsAlertDisplayed = false
    @EnvironmentObject var hostingSplitView: HostingSplitView

    private var inset: Bool {
        hostingSplitView.isSplit
    }
    
    private let languageOptions = [LanguageSelection.none] + LanguageIso639_1.allCases.filter { $0.canFilterGoogleSearchResults }.map { .some($0) }

    var body: some View {
        SwiftUI.List {
            Section(
                header: HeaderText("Appearance", inset: inset),
                footer: FooterText("Enable Expanded Descriptions to automatically show each book's full description.", inset: inset)
            ) {
                Toggle(isOn: $expandedDescriptions) {
                    Text("Expanded Descriptions")
                }
            }

            Section(
                header: HeaderText("Progress", inset: inset),
                footer: FooterText("Choose whether to default to Page Number or Percentage when setting progress.", inset: inset)
            ) {
                NavigationLink(
                    destination: SelectionForm<ProgressType>(
                        options: [.page, .percentage],
                        selectedOption: $progressType
                    ).navigationBarTitle("Default Progress Type")
                ) {
                    HStack {
                        Text("Progress Type")
                        Spacer()
                        Text(progressType.description)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(
                header: HeaderText("Language", inset: inset),
                footer: FooterText("""
                    By default, Reading List prioritises search results based on their language and your location. To instead \
                    restrict search results to be of a specific language only, select a language above.
                    """, inset: inset)
            ) {
                Toggle(isOn: $prepopulateLastLanguageSelection) {
                    Text("Remember Last Selection")
                }
                NavigationLink(
                    destination: SelectionForm<LanguageSelection>(
                        options: languageOptions,
                        selectedOption: $restrictSearchResultsTo
                    ).navigationBarTitle("Language Restriction")
                ) {
                    HStack {
                        Text("Restrict Search Results")
                        Spacer()
                        Text(restrictSearchResultsTo.description).foregroundColor(.secondary)
                    }
                }
            }

            Section(
                header: HeaderText("Analytics", inset: inset),
                footer: FooterText("""
                Crash reports can be automatically sent to help me detect and fix issues. Analytics can \
                be used to help gather usage statistics for different features. This never includes any \
                details of your books.\
                \(BuildInfo.thisBuild.type != .testFlight ? "" : " If Beta testing, these cannot be disabled.")
                """, inset: inset)) {

                Toggle(isOn: Binding(get: { sendCrashReports }, set: { newValue in
                    if !newValue {
                        crashReportsAlertDisplated = true
                    } else {
                        sendCrashReports = true
                        UserEngagement.logEvent(.enableCrashReports)
                    }
                })) {
                    Text("Send Crash Reports")
                }.alert(isPresented: $crashReportsAlertDisplated) {
                    crashReportsAlert
                }

                Toggle(isOn: Binding(get: { sendAnalytics }, set: { newValue in
                    if !newValue {
                        analyticsAlertDisplayed = true
                    } else {
                        sendAnalytics = true
                        UserEngagement.logEvent(.enableAnalytics)
                    }
                })) {
                    Text("Send Analytics")
                }.alert(isPresented: $analyticsAlertDisplayed) {
                    analyticsAlert
                }
            }
        }
        .possiblyInsetGroupedListStyle(inset: hostingSplitView.isSplit)
        .navigationBarTitle("General", displayMode: .inline)
    }

    var crashReportsAlert: Alert {
        Alert(
            title: Text("Turn Off Crash Reports?"),
            message: Text("""
            Anonymous crash reports alert me if this app crashes, to help me fix bugs. \
            This never includes any information about your books. Are you \
            sure you want to turn this off?
            """),
            primaryButton: .default(Text("Leave On")) {
                sendCrashReports = true
            },
            secondaryButton: .destructive(Text("Turn Off")) {
                sendCrashReports = false
                UserEngagement.logEvent(.disableCrashReports)
            }
        )
    }

    var analyticsAlert: Alert {
        Alert(
            title: Text("Turn Off Analytics?"),
            message: Text("""
            Anonymous usage statistics help prioritise development. This never includes \
            any information about your books. Are you sure you want to turn this off?
            """),
            primaryButton: .default(Text("Leave On")) {
                sendAnalytics = true
            },
            secondaryButton: .destructive(Text("Turn Off")) {
                sendAnalytics = false
                UserEngagement.logEvent(.disableAnalytics)
            }
        )
    }
}

extension ProgressType: Identifiable {
    var id: Int { rawValue }
}

extension LanguageSelection: Identifiable {
    var id: String {
        switch self {
        case .none: return ""
        // Not in practise used by this form; return some arbitrary unique value
        case .blank: return "!"
        case .some(let language): return language.rawValue
        }
    }
}

struct GeneralNew_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            General().environmentObject(HostingSplitView())
        }
    }
}
