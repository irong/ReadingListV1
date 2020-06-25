import Foundation
import PersistedPropertyWrapper

struct AppLaunchHistory {
    private init() { }

    @Persisted(encodedDataKey: "lastLaunchedVersion")
    static var lastLaunchedVersion: Version?

    /// The user facing description of the most recent version (e.g. "1.5" or "1.6.1 beta 3") for which the persistent store has been successfully initialised.
    @Persisted("mostRecentWorkingVersion")
    static var mostRecentWorkingVersionDescription: String?

    @Persisted("appStartupCount", defaultValue: 0)
    static var appOpenedCount: Int

    @Persisted("lastAppliedUpgradeAction")
    static var lastAppliedUpgradeAction: Int?
}
