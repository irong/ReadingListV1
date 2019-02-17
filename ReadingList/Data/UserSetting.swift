import Foundation

// FUTURE:
// Compile fails in Release mode if this file is located in ReadingList_Foundation, with errors like:
//     Undefined symbols for architecture armv7
//      > Symbol: protocol witness table for Swift.Bool : ReadingList_Foundation.DefaultsStorable in ReadingList_Foundation

/** Storable by this framework */
public protocol UserSettingType { }

/** Natively storable in UserDefaults */
protocol DefaultsStorable: UserSettingType { }

extension Int: DefaultsStorable {}
extension Int16: DefaultsStorable {}
extension Int32: DefaultsStorable {}
extension Int64: DefaultsStorable {}
extension String: DefaultsStorable {}
extension URL: DefaultsStorable {}
extension Bool: DefaultsStorable {}
extension Double: DefaultsStorable {}
extension Float: DefaultsStorable {}
extension Data: DefaultsStorable {}

extension Array: DefaultsStorable, UserSettingType where Element: DefaultsStorable {}
extension Dictionary: DefaultsStorable, UserSettingType where Key == String, Value: DefaultsStorable {}
extension Optional: UserSettingType where Wrapped: UserSettingType {}

/* Can be used to hold a collection of static UserSetting variables */
public class UserSettingsCollection {
    fileprivate init() {}
}

/* Stores information about a setting. */
public class UserSetting<Type: UserSettingType>: UserSettingsCollection {
    public let key: String
    fileprivate let defaultValue: Type?

    public init(_ key: String, defaultValue: Type) {
        self.key = key
        self.defaultValue = defaultValue
    }

    private init(key: String) {
        self.key = key
        self.defaultValue = nil
    }
}

/* Protocol to enable constraints on optionality */
public protocol OptionalType {
    associatedtype Wrapped
}
extension Optional: OptionalType { }

/* Initialiser to allow optional-type UserDefaults to not have to specify that the default is nil */
public extension UserSetting where Type: UserSettingType, Type: OptionalType, Type.Wrapped: UserSettingType {
    convenience init(_ key: String) {
        self.init(key: key)
    }
}

//swiftlint:disable redundant_nil_coalescing
public extension UserDefaults {
    subscript<T: DefaultsStorable>(key: UserSetting<T>) -> T {
        get {
            return self.object(forKey: key.key) as? T ?? key.defaultValue!
        }
        set {
            self.set(newValue, forKey: key.key)
        }
    }

    subscript<T: DefaultsStorable>(key: UserSetting<T?>) -> T? {
        get {
            return self.object(forKey: key.key) as? T ?? key.defaultValue ?? nil
        }
        set {
            self.set(newValue, forKey: key.key)
        }
    }

    subscript<T: RawRepresentable>(key: UserSetting<T>) -> T where T.RawValue: DefaultsStorable {
        get {
            guard let rawValue = self.object(forKey: key.key) as? T.RawValue, let wrappedValue = T(rawValue: rawValue) else {
                return key.defaultValue!
            }
            return wrappedValue
        }
        set {
            self.set(newValue.rawValue, forKey: key.key)
        }
    }

    subscript<T: RawRepresentable>(key: UserSetting<T?>) -> T? where T.RawValue: DefaultsStorable {
        get {
            guard let rawValue = self.object(forKey: key.key) as? T.RawValue, let wrappedValue = T(rawValue: rawValue) else {
                return key.defaultValue ?? nil
            }
            return wrappedValue
        }
        set {
            self.set(newValue?.rawValue, forKey: key.key)
        }
    }
}
//swiftlint:enable redundant_nil_coalescing
