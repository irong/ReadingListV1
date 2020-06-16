import Foundation

struct UserDefaultsBackingConvertor<NonOptionalExposed, Stored> {
    let toStorage: (NonOptionalExposed) -> Stored
    let toExposed: (Stored) -> NonOptionalExposed

    static func notConverted<NonOptionalExposed>() -> UserDefaultsBackingConvertor<NonOptionalExposed, NonOptionalExposed> {
        return UserDefaultsBackingConvertor<NonOptionalExposed, NonOptionalExposed>(
            toStorage: { $0 },
            toExposed: { $0 }
        )
    }

    static func rawRepresentable<NonOptionalExposed, Stored>() -> UserDefaultsBackingConvertor<NonOptionalExposed, Stored>
        where NonOptionalExposed: RawRepresentable, NonOptionalExposed.RawValue == Stored {
            return UserDefaultsBackingConvertor<NonOptionalExposed, Stored>(
                toStorage: { $0.rawValue },
                toExposed: { NonOptionalExposed(rawValue: $0)! }
            )
    }

    static func codable<NonOptionalExposed>() -> UserDefaultsBackingConvertor<NonOptionalExposed, Data> where NonOptionalExposed: Codable {
        return UserDefaultsBackingConvertor<NonOptionalExposed, Data>(
            toStorage: { try! JSONEncoder().encode($0) },
            toExposed: { try! JSONDecoder().decode(NonOptionalExposed.self, from: $0) }
        )
    }
}

@propertyWrapper public struct UserDefaultsBacked<Exposed, NonOptionalExposed, Stored> {
    let key: String
    let defaultValue: Exposed
    let valueConvertor: UserDefaultsBackingConvertor<NonOptionalExposed, Stored>

    fileprivate init(key: String, defaultValue: Exposed, valueConvertor: UserDefaultsBackingConvertor<NonOptionalExposed, Stored>) {
        self.key = key
        self.defaultValue = defaultValue
        self.valueConvertor = valueConvertor
    }

    public var wrappedValue: Exposed {
        get {
            // Get the object stored for the given key, and cast it to the Stored type. If the object is present but
            // not castable, this is a fatal error.
            guard let typelessStored = UserDefaults.standard.value(forKey: key) else { return defaultValue }
            guard let stored = typelessStored as? Stored else {
                fatalError("Value stored at key \(key) was not of type \(String(describing: Stored.self))")
            }

            let nonOptionalExposed = valueConvertor.toExposed(stored)
            return nonOptionalExposed as! Exposed
        }
        set {
            if let optional = newValue as? AnyOptional, optional.isNil {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            let nonOptionalNewValue = newValue as! NonOptionalExposed
            let valueToStore = valueConvertor.toStorage(nonOptionalNewValue)
            UserDefaults.standard.setValue(valueToStore, forKey: key)
        }
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed,
                                            NonOptionalExposed == Stored,
                                            Stored: UserDefaultsPrimitive {

    init(key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .notConverted())
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed?,
    NonOptionalExposed == Stored,
    Stored: UserDefaultsPrimitive {

    init(key: String) {
        self.init(key: key, defaultValue: nil, valueConvertor: .notConverted())
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed,
                                            NonOptionalExposed: RawRepresentable,
                                            Stored == NonOptionalExposed.RawValue,
                                            Stored: UserDefaultsPrimitive {

    init(key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .rawRepresentable())
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed?,
                                            NonOptionalExposed: RawRepresentable,
                                            Stored == NonOptionalExposed.RawValue,
                                            Stored: UserDefaultsPrimitive {

    init(key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .rawRepresentable())
    }

    init(key: String) {
        self.init(key: key, defaultValue: nil)
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed,
                                            NonOptionalExposed: Codable,
                                            Stored == Data {

    init(dataKey key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .codable())
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed?,
                                            NonOptionalExposed: Codable,
                                            Stored == Data {

    init(dataKey key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .codable())
    }

    init(dataKey key: String) {
        self.init(dataKey: key, defaultValue: nil)
    }
}

public protocol UserDefaultsPrimitive {}
extension Int: UserDefaultsPrimitive {}
extension Int16: UserDefaultsPrimitive {}
extension Int32: UserDefaultsPrimitive {}
extension Int64: UserDefaultsPrimitive {}
extension String: UserDefaultsPrimitive {}
extension URL: UserDefaultsPrimitive {}
extension Bool: UserDefaultsPrimitive {}
extension Double: UserDefaultsPrimitive {}
extension Float: UserDefaultsPrimitive {}
extension Data: UserDefaultsPrimitive {}

// Since our property wrapper's Value type isn't optional, but can still contain nil values, we'll have to introduce this
// protocol to enable us to cast any assigned value into a type that we can compare against nil:
private protocol AnyOptional {
    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    var isNil: Bool { self == nil }
}
