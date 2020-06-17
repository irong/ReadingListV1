import Foundation
import ReadingList_Foundation

struct AppLaunchHistory {
    private init() { }

    @UserDefaultsBacked(codingKey: "lastLaunchedVersion")
    static var lastLaunchedVersion: Version?

    /// The user facing description of the most recent version (e.g. "1.5" or "1.6.1 beta 3") for which the persistent store has been successfully initialised.
    @UserDefaultsBacked(key: "mostRecentWorkingVersion")
    static var mostRecentWorkingVersionDescription: String?

    @UserDefaultsBacked(key: "appStartupCount", defaultValue: 0)
    static var appOpenedCount: Int

    @UserDefaultsBacked(key: "lastAppliedUpgradeAction")
    static var lastAppliedUpgradeAction: Int?
}
