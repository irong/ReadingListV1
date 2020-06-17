import ReadingList_Foundation

struct GeneralSettings {
    private init() { }

    @UserDefaultsBacked(key: "searchLanguageRestriction")
    static var searchLanguageRestriction: LanguageIso639_1?

    @UserDefaultsBacked(key: "prepopulateLastLanguageSelection", defaultValue: true)
    static var prepopulateLastLanguageSelection: Bool

    @UserDefaultsBacked(key: "showExpandedDescription", defaultValue: false)
    static var showExpandedDescription: Bool

    @UserDefaultsBacked(key: "defaultProgressType", defaultValue: .page)
    static var defaultProgressType: ProgressType

    @UserDefaultsBacked(key: "addCustomBooksToTopOfCustom", defaultValue: false)
    static var addBooksToTopOfCustom: Bool

    @available(iOS, obsoleted: 13.0)
    @UserDefaultsBacked(key: "theme", defaultValue: .normal)
    static var theme: Theme
}
