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

extension UIColor {
    static var customHexColorCache = [UInt32: UIColor]()

    static func hex(_ hex: UInt32) -> UIColor {
        if let cachedColor = UIColor.customHexColorCache[hex] { return cachedColor }
        let color = UIColor(fromHex: hex)
        customHexColorCache[hex] = color
        return color
    }
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

extension Theme {

    var isDark: Bool {
        return self == .dark || self == .black
    }

    var tint: UIColor {
        return isDark ? UIColor.hex(0x136cd6) : .buttonBlue
    }

    var greenButtonColor: UIColor {
        return isDark ? UIColor.hex(0x2ca55d) : .flatGreen
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
        case .normal: return UIColor.hex(0x686868)
        case .dark: return .lightGray
        case .black: return .lightGray
        }
    }

    var placeholderTextColor: UIColor {
        switch self {
        case .normal: return UIColor.hex(0xCDCDD3)
        case .dark: return UIColor.hex(0x404040)
        case .black: return UIColor.hex(0x363636)
        }
    }

    var tableBackgroundColor: UIColor {
        switch self {
        case .normal: return .groupTableViewBackground
        case .dark: return UIColor.hex(0x282828)
        case .black: return UIColor.hex(0x080808)
        }
    }

    var cellBackgroundColor: UIColor {
        return viewBackgroundColor
    }

    var selectedCellBackgroundColor: UIColor {
        switch self {
        case .normal: return UIColor.hex(0xD9D9D9)
        case .dark: return .black
        case .black: return UIColor.hex(0x191919)
        }
    }

    var cellSeparatorColor: UIColor {
        switch self {
        case .normal: return UIColor.hex(0xD6D6D6)
        case .dark: return UIColor.hex(0x4A4A4A)
        case .black: return UIColor.hex(0x282828)
        }
    }

    var viewBackgroundColor: UIColor {
        switch self {
        case .normal: return .white
        case .dark: return UIColor.hex(0x191919)
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
        ImageRow.defaultCellUpdate = initialiseCell(_:_:)
        SegmentedRow<BookReadState>.defaultCellUpdate = initialiseCell(_:_:)
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
