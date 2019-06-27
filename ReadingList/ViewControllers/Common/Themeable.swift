import UIKit
import Foundation
import Eureka
import ImageRow
import SafariServices
import ReadingList_Foundation

@objc enum Theme: Int, UserSettingType, CaseIterable {
    case normal = 1
    case dark = 2
    case black = 3
}

extension Theme: CustomStringConvertible {
    var description: String {
        switch self {
        case .normal: return "Default"
        case .dark: return "Dark"
        case .black: return "Black"
        }
    }
}

enum ColorAsset: String {
    case buttonBlue = "ButtonBlue"
    case buttonGreen = "ButtonGreen"
    case darkButtonBlue = "DarkButtonBlue"
    case darkButtonGreen = "DarkButtonGreen"
    case subtitleText = "SubtitleText"
    case veryDark = "VeryDark"
    case extremelyDark = "ExtremelyDark"
    case veryLight = "VeryLight"
    case placeholderText = "PlaceholderText"
    case darkPlaceholderText = "DarkPlaceholderText"
    case blackPlaceholderText = "BlackPlaceholderText"
    case lightBlueCellSelection = "LightBlueCellSelection"
}

extension UIColor {
    convenience init(_ assetName: ColorAsset) {
        self.init(named: assetName.rawValue)!
    }
}

extension Theme {

    var isDark: Bool {
        return self == .dark || self == .black
    }

    var tint: UIColor {
        return isDark ? UIColor(.darkButtonBlue) : UIColor(.buttonBlue)
    }

    var greenButtonColor: UIColor {
        return isDark ? UIColor(.darkButtonGreen) : UIColor(.buttonGreen)
    }

    var keyboardAppearance: UIKeyboardAppearance {
        return isDark ? .dark : .default
    }

    var barStyle: UIBarStyle {
        return isDark ? .black : .default
    }

    var statusBarStyle: UIStatusBarStyle {
        return isDark ? .lightContent : .default
    }

    var titleTextColor: UIColor {
        return isDark ? .white : .black
    }

    var subtitleTextColor: UIColor {
        switch self {
        case .normal: return UIColor(.subtitleText)
        case .dark: return .lightGray
        case .black: return .lightGray
        }
    }

    var placeholderTextColor: UIColor {
        switch self {
        case .normal: return UIColor(.placeholderText)
        case .dark: return UIColor(.darkPlaceholderText)
        case .black: return UIColor(.blackPlaceholderText)
        }
    }

    var tableBackgroundColor: UIColor {
        switch self {
        case .normal: return .groupTableViewBackground
        case .dark: return UIColor(.veryDark)
        case .black: return UIColor(.extremelyDark)
        }
    }

    var cellBackgroundColor: UIColor {
        return viewBackgroundColor
    }

    var selectedCellBackgroundColor: UIColor {
        switch self {
        case .normal: return UIColor(.veryLight)
        case .dark: return .black
        case .black: return UIColor(.veryDark)
        }
    }

    var cellSeparatorColor: UIColor {
        switch self {
        case .normal: return UIColor(.veryLight)
        case .dark: return UIColor(.veryDark)
        case .black: return UIColor(.veryDark)
        }
    }

    var viewBackgroundColor: UIColor {
        switch self {
        case .normal: return .white
        case .dark: return UIColor(.veryDark)
        case .black: return .black
        }
    }
}

extension UITableViewCell {
    func defaultInitialise(withTheme theme: Theme) {
        backgroundColor = theme.cellBackgroundColor
        textLabel?.textColor = theme.titleTextColor
        detailTextLabel?.textColor = theme.titleTextColor
        if selectionStyle != .none {
            setSelectedBackgroundColor(theme.selectedCellBackgroundColor)
        }
    }
}

fileprivate extension UIViewController {
    /**
     Must only called on a ThemableViewController.
    */
    @objc func transitionThemeChange() {
        // This function is defined as an extension of UIViewController rather than in ThemableViewController
        // since it must be @objc, and that is not possible in protocol extensions.
        guard let themable = self as? ThemeableViewController else {
            assertionFailure("transitionThemeChange called on a non-themable controller"); return
        }
        UIView.transition(with: self.view, duration: 0.3, options: [.beginFromCurrentState, .transitionCrossDissolve], animations: {
            themable.initialise(withTheme: UserDefaults.standard[.theme])
            themable.themeSettingDidChange?()
        }, completion: nil)
    }
}

@objc protocol ThemeableViewController where Self: UIViewController {
    @objc func initialise(withTheme theme: Theme)
    @objc optional func themeSettingDidChange()
}

extension ThemeableViewController {
    func monitorThemeSetting() {
        initialise(withTheme: UserDefaults.standard[.theme])
        NotificationCenter.default.addObserver(self, selector: #selector(transitionThemeChange), name: .ThemeSettingChanged, object: nil)
    }
}

extension UIViewController {
    func presentThemedSafariViewController(_ url: URL) {
        let safariVC = SFSafariViewController(url: url)
        if UserDefaults.standard[.theme].isDark {
            safariVC.preferredBarTintColor = .black
        }
        present(safariVC, animated: true, completion: nil)
    }

    func inThemedNavController(modalPresentationStyle: UIModalPresentationStyle = .formSheet) -> UINavigationController {
        let nav = ThemedNavigationController(rootViewController: self)
        nav.modalPresentationStyle = modalPresentationStyle
        return nav
    }
}

extension UITabBarController: ThemeableViewController {
    func initialise(withTheme theme: Theme) {
        tabBar.initialise(withTheme: theme)

        let useTranslucency = traitCollection.horizontalSizeClass != .regular
        tabBar.setTranslucency(useTranslucency, colorIfNotTranslucent: theme.viewBackgroundColor)
    }
}

extension UIToolbar {
    func initialise(withTheme theme: Theme) {
        barStyle = theme.barStyle
    }
}

extension UITableViewController: ThemeableViewController {
    func initialise(withTheme theme: Theme) {
        navigationItem.searchController?.searchBar.initialise(withTheme: theme)
        tableView.initialise(withTheme: theme)
    }

    func themeSettingDidChange() {
        // Saw some weird artifacts which went away when the selected rows were deselected
        let selectedRow = tableView.indexPathForSelectedRow
        if let selectedRow = selectedRow { tableView.deselectRow(at: selectedRow, animated: false) }
        tableView.reloadData()
        if let selectedRow = selectedRow { tableView.selectRow(at: selectedRow, animated: false, scrollPosition: .none) }
    }
}

extension FormViewController: ThemeableViewController {
    func initialise(withTheme theme: Theme) {
        tableView.initialise(withTheme: theme)
    }

    func themeSettingDidChange() {
        // Saw some weird artifacts which went away when the selected rows were deselected
        let selectedRow = tableView.indexPathForSelectedRow
        if let selectedRow = selectedRow { tableView.deselectRow(at: selectedRow, animated: false) }
        tableView.reloadData()
        if let selectedRow = selectedRow { tableView.selectRow(at: selectedRow, animated: false, scrollPosition: .none) }
    }
}

class ThemedSplitViewController: UISplitViewController, UISplitViewControllerDelegate, ThemeableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredDisplayMode = .allVisible
        delegate = self

        monitorThemeSetting()
    }

    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        return true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // This is called at app startup
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            initialise(withTheme: UserDefaults.standard[.theme])
        }
    }

    func initialise(withTheme theme: Theme) {
        view.backgroundColor = theme.cellSeparatorColor

        // This attempts to allieviate this bug: https://stackoverflow.com/q/32507975/5513562
        (masterNavigationController as! ThemedNavigationController).initialise(withTheme: theme)
        (detailNavigationController as? ThemedNavigationController)?.initialise(withTheme: theme)
        (tabBarController as! TabBarController).initialise(withTheme: theme)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // This override is placed on the base view controller type - the SplitViewController - so that
        // it only needs to be implemented once.
        return UserDefaults.standard[.theme].statusBarStyle
    }
}

class ThemedNavigationController: UINavigationController, ThemeableViewController {
    var hasAppeared = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Determine whether the nav bar should be transparent or not from the horizontal
        // size class of the parent split view controller. We can't ask *this* view controller,
        // as its size class is not necessarily the same as the whole app.
        // Run this after the view has loaded so that the parent VC is available.
        if !hasAppeared {
            monitorThemeSetting()
            hasAppeared = true
        }
    }

    func initialise(withTheme theme: Theme) {
        toolbar?.initialise(withTheme: theme)
        navigationBar.initialise(withTheme: theme)

        let translucent = splitViewController?.traitCollection.horizontalSizeClass != .regular
        navigationBar.setTranslucency(translucent, colorIfNotTranslucent: UserDefaults.standard[.theme].viewBackgroundColor)
    }
}

class ThemedSelectorViewController<T: Equatable>: SelectorViewController<SelectorRow<PushSelectorCell<T>>> {
    override func viewDidLoad() {
        super.viewDidLoad()
        monitorThemeSetting()
    }
}

final class ThemedPushRow<T: Equatable>: _PushRow<PushSelectorCell<T>>, RowType {
    required init(tag: String?) {
        super.init(tag: tag)
        presentationMode = .show(controllerProvider: .callback { ThemedSelectorViewController() }) {
            $0.navigationController?.popViewController(animated: true)
        }
    }
}

extension UINavigationBar {
    func initialise(withTheme theme: Theme) {
        barStyle = theme.barStyle
        titleTextAttributes = [.foregroundColor: theme.titleTextColor]
        largeTitleTextAttributes = [.foregroundColor: theme.titleTextColor]
    }

    func setTranslucency(_ translucent: Bool, colorIfNotTranslucent: UIColor) {
        isTranslucent = translucent
        barTintColor = translucent ? nil : colorIfNotTranslucent
    }
}

extension UISearchBar {
    func initialise(withTheme theme: Theme) {
        keyboardAppearance = theme.keyboardAppearance
        barStyle = theme.barStyle
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).defaultTextAttributes = [.foregroundColor: theme.titleTextColor]
    }
}

extension UITableView {
    func initialise(withTheme theme: Theme) {
        backgroundColor = theme.tableBackgroundColor
        separatorColor = theme.cellSeparatorColor
    }
}

extension UITabBar {
    func initialise(withTheme theme: Theme) {
        barStyle = theme.barStyle
    }

    func setTranslucency(_ translucent: Bool, colorIfNotTranslucent: UIColor) {
        isTranslucent = translucent
        barTintColor = translucent ? nil : colorIfNotTranslucent
    }
}

extension StartFinishButton {
    func initialise(withTheme theme: Theme) {
        startColor = theme.tint
        finishColor = theme.greenButtonColor
    }
}

extension Theme {
    func configureForms() {

        func initialiseCell(_ cell: UITableViewCell, _: Any? = nil) {
            cell.defaultInitialise(withTheme: self)
        }

        SwitchRow.defaultCellUpdate = initialiseCell(_:_:)
        DateRow.defaultCellUpdate = initialiseCell(_:_:)
        ThemedPushRow<Theme>.defaultCellUpdate = initialiseCell(_:_:)
        ListCheckRow<Theme>.defaultCellUpdate = initialiseCell(_:_:)
        ThemedPushRow<ProgressType>.defaultCellUpdate = initialiseCell(_:_:)
        ListCheckRow<ProgressType>.defaultCellUpdate = initialiseCell(_:_:)
        ImageRow.defaultCellUpdate = initialiseCell(_:_:)
        SegmentedRow<BookReadState>.defaultCellUpdate = initialiseCell(_:_:)
        SegmentedRow<ProgressType>.defaultCellUpdate = initialiseCell(_:_:)
        LabelRow.defaultCellUpdate = initialiseCell(_:_:)
        AuthorRow.defaultCellUpdate = initialiseCell(_:_:)
        PickerInlineRow<LanguageSelection>.defaultCellUpdate = { cell, _ in
            initialiseCell(cell)
            cell.tintColor = self.titleTextColor
        }
        PickerInlineRow<LanguageSelection>.InlineRow.defaultCellUpdate = { cell, _ in
            initialiseCell(cell)
            cell.pickerTextAttributes = [.foregroundColor: self.titleTextColor]
        }
        ButtonRow.defaultCellUpdate = { cell, _ in
            // Cannot use the default initialise since it turns the button text a plain colour
            cell.backgroundColor = self.cellBackgroundColor
            cell.setSelectedBackgroundColor(self.selectedCellBackgroundColor)
        }
        StarRatingRow.defaultCellUpdate = { cell, _ in
            initialiseCell(cell)
            cell.leftLabel.textColor = self.titleTextColor
        }
        IntRow.defaultCellUpdate = { cell, _ in
            initialiseCell(cell)
            cell.textField.textColor = self.titleTextColor
            cell.textField.keyboardAppearance = self.keyboardAppearance
        }
        Int32Row.defaultCellUpdate = { cell, _ in
            initialiseCell(cell)
            cell.textField.textColor = self.titleTextColor
            cell.textField.keyboardAppearance = self.keyboardAppearance
        }
        Int64Row.defaultCellUpdate = { cell, _ in
            initialiseCell(cell)
            cell.textField.textColor = self.titleTextColor
            cell.textField.keyboardAppearance = self.keyboardAppearance
        }
        TextAreaRow.defaultCellUpdate = { cell, row in
            initialiseCell(cell)
            cell.placeholderLabel?.textColor = self.placeholderTextColor
            cell.textView.backgroundColor = self.cellBackgroundColor
            cell.textView.textColor = self.titleTextColor
            cell.textView.keyboardAppearance = self.keyboardAppearance
        }
        TextRow.defaultCellSetup = { cell, row in
            row.placeholderColor = self.placeholderTextColor
        }
        TextRow.defaultCellUpdate = { cell, row in
            initialiseCell(cell)
            cell.textField.keyboardAppearance = self.keyboardAppearance
            cell.textField.textColor = self.titleTextColor
        }
    }
}
