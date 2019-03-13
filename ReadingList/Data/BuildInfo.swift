import Foundation
import ReadingList_Foundation

class BuildInfo {
    enum BuildType {
        case debug
        case testFlight
        case appStore
    }

    static var appVersion: String {
        return Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    }

    static var appBuildNumber: String {
        return Bundle.main.infoDictionary!["CFBundleVersion"] as! String
    }

    private static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    static var isDebug: Bool {
        #if DEBUG || arch(i386) || arch(x86_64)
            return true
        #else
            return false
        #endif
    }

    static var appConfiguration: BuildType {
        if isDebug {
            return .debug
        } else if isTestFlight {
            return .testFlight
        } else {
            return .appStore
        }
    }
}

extension BuildInfo.BuildType {
    var fullDescription: String {
        switch BuildInfo.appConfiguration {
        case .appStore: return "\(BuildInfo.appVersion)"
        case .testFlight: return "\(BuildInfo.appVersion) (Build \(BuildInfo.appBuildNumber))"
        case .debug: return "\(BuildInfo.appVersion) Debug"
        }
    }

    var versionAndConfiguration: String {
        switch BuildInfo.appConfiguration {
        case .appStore: return BuildInfo.appVersion
        case .testFlight: return "\(BuildInfo.appVersion) (Beta)"
        case .debug: return "\(BuildInfo.appVersion) (Debug)"
        }
    }
}
