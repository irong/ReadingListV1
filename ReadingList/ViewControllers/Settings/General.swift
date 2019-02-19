import Foundation
import UIKit
import Eureka
import ReadingList_Foundation

class General: FormViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        form +++ SelectableSection<ListCheckRow<Theme>>(header: "Theme", footer: "Change the appearance of Reading List.",
                                                        selectionType: .singleSelection(enableDeselection: false)) {
            $0.onSelectSelectableRow = { _, row in
                UserDefaults.standard[.theme] = row.value!
                NotificationCenter.default.post(name: .ThemeSettingChanged, object: nil)
                UserEngagement.logEvent(.changeTheme)
                UserEngagement.onReviewTrigger()
            }
        }
            <<< themeRow(.normal, name: "Default")
            <<< themeRow(.dark, name: "Dark")
            <<< themeRow(.black, name: "Black")

            +++ Section(header: "Search Results", footer: """
                By default, Reading List prioritises search results based on their language and your location. To instead
                restrict search results to be of a specific language only, select a language above.
                """)
                <<< PickerInlineRow<LanguageSelection> {
                    $0.title = "Language Restriction"
                    $0.options = [.none] + LanguageIso639_1.allCases.filter { $0.canFilterGoogleSearchResults }.map { .some($0) }
                    $0.value = {
                        if let languageRestriction = UserDefaults.standard[.searchLanguageRestriction] {
                            return .some(languageRestriction)
                        } else {
                            return LanguageSelection.none
                        }
                    }()
                    $0.onChange {
                        if let languageSelection = $0.value, case let .some(language) = languageSelection {
                            UserDefaults.standard[.searchLanguageRestriction] = language
                        } else {
                            UserDefaults.standard[.searchLanguageRestriction] = nil
                        }
                    }
                }

            +++ Section(header: "Analytics", footer: """
                Crash reports can be automatically sent to help me detect and fix issues. Analytics can \
                be used to help gather usage statistics for different features. This never includes any \
                details of your books.\
                \(BuildInfo.appConfiguration != .testFlight ? "" : " If Beta testing, these cannot be disabled.")
                """)
                <<< SwitchRow {
                    $0.title = "Send Crash Reports"
                    $0.disabled = Condition(booleanLiteral: BuildInfo.appConfiguration == .testFlight)
                    $0.onChange { [unowned self] in
                        self.crashReportsSwitchChanged($0)
                    }
                    $0.value = UserEngagement.sendCrashReports
                }
                <<< SwitchRow {
                    $0.title = "Send Analytics"
                    $0.disabled = Condition(booleanLiteral: BuildInfo.appConfiguration == .testFlight)
                    $0.onChange { [unowned self] in
                        self.analyticsSwitchChanged($0)
                    }
                    $0.value = UserEngagement.sendAnalytics
                }

        monitorThemeSetting()
    }

    func themeRow(_ theme: Theme, name: String) -> ListCheckRow<Theme> {
        return ListCheckRow<Theme> {
            $0.title = name
            $0.selectableValue = theme
            $0.value = UserDefaults.standard[.theme] == theme ? theme : nil
        }
    }

    func crashReportsSwitchChanged(_ sender: _SwitchRow) {
        guard let switchValue = sender.value else { return }
        if switchValue {
            UserDefaults.standard[.sendCrashReports] = true
            UserEngagement.logEvent(.enableCrashReports)
        } else {
            // If this is being turned off, let's try to persuade them to turn it back on
            persuadeToKeepOn(title: "Turn Off Crash Reports?", message: """
                Anonymous crash reports alert me if this app crashes, to help me fix bugs. \
                This never includes any information about your books. Are you \
                sure you want to turn this off?
                """) { result in
                if result {
                    sender.value = true
                    sender.reload()
                } else {
                    UserEngagement.logEvent(.disableCrashReports)
                    UserDefaults.standard[.sendCrashReports] = false
                }
            }
        }
    }

    func analyticsSwitchChanged(_ sender: _SwitchRow) {
        guard let switchValue = sender.value else { return }
        if switchValue {
            UserDefaults.standard[.sendAnalytics] = true
            UserEngagement.logEvent(.enableAnalytics)
        } else {
            // If this is being turned off, let's try to persuade them to turn it back on
            persuadeToKeepOn(title: "Turn Off Analytics?", message: """
                Anonymous usage statistics help prioritise development. This never includes \
                any information about your books. Are you sure you want to turn this off?
                """) { result in
                if result {
                    sender.value = true
                    sender.reload()
                } else {
                    UserEngagement.logEvent(.disableAnalytics)
                    UserDefaults.standard[.sendAnalytics] = false
                }
            }
        }
    }

    func persuadeToKeepOn(title: String, message: String, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Turn Off", style: .destructive) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Leave On", style: .default) { _ in
            completion(true)
        })
        present(alert, animated: true)
    }
}

extension Notification.Name {
    static let ThemeSettingChanged = Notification.Name("theme-setting-changed")
}
