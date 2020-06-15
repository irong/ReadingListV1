import Foundation
import ReadingList_Foundation

struct LightweightDataStore {
    private init() {}

    /// This is not always true; tip functionality predates this setting...
    @UserDefaultsBacked(key: "hasEverTipped", defaultValue: false)
    static var hasEverTipped: Bool

    @UserDefaultsBacked(key: "lastSelectedLanguage")
    static var lastSelectedLanguage: LanguageIso639_1?
}
