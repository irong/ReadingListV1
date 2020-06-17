import Foundation

/// Expresses that a property should be read from and saved to `UserDefaults`. Supports properties of the following types: those which can be natively stored in `UserDefaults`,
/// `RawRepresentable` types where the `RawType` is one which an be natively stored in `UserDefaults`, and any `Codable` type.
@propertyWrapper public struct UserDefaultsBacked<Exposed, NonOptionalExposed, Stored> where Stored: UserDefaultsPrimitive {
    // The use of three generic arguments here is necessary as we want to be able to use this property wrapped on properties
    // of type Optional<T>, but also inspect the underlying type T. We cannot check whether a generic type is an Optional<T>,
    // so instead we provide two 'slots' for the types: the Exposed type (which may be optional), and the NonOptionalExposed
    // type. If Exposed is equal to Optional<T>, then NonOptionalExposed must be equal to T; otherwise NonOptionalExposed
    // must be equal to Exposed.
    let key: String
    let defaultValue: Exposed
    private let valueConvertor: StorageConvertor<NonOptionalExposed, Stored>

    /// A utility which can convert between two types.
    struct StorageConvertor<Exposed, Stored> where Stored: UserDefaultsPrimitive {
        let toStorage: (Exposed) -> Stored
        let toExposed: (Stored) -> Exposed

        static func notConverted<Exposed>() -> StorageConvertor<Exposed, Exposed> where Exposed: UserDefaultsPrimitive {
            StorageConvertor<Exposed, Exposed>(
                toStorage: { $0 },
                toExposed: { $0 }
            )
        }

        static func rawRepresentable<Exposed, Stored>() -> StorageConvertor<Exposed, Stored> where Exposed: RawRepresentable,
                                                                                                    Exposed.RawValue == Stored {
            StorageConvertor<Exposed, Stored>(
                toStorage: { $0.rawValue },
                toExposed: { Exposed(rawValue: $0)! }
            )
        }

        static func codable<Exposed>() -> StorageConvertor<Exposed, Data> where Exposed: Codable {
            StorageConvertor<Exposed, Data>(
                toStorage: { try! JSONEncoder().encode($0) },
                toExposed: { try! JSONDecoder().decode(Exposed.self, from: $0) }
            )
        }
    }

    fileprivate init(key: String, defaultValue: Exposed, valueConvertor: StorageConvertor<NonOptionalExposed, Stored>) {
        // We cannot check this condition at compile time. We only publicly expose valid initialisation
        // functions, but to be safe let's check at runtime that the types are correct.
        guard Exposed.self == NonOptionalExposed.self || Exposed.self == Optional<NonOptionalExposed>.self else {
            preconditionFailure("Invalid UserDefaultsBacked generic arguments")
        }
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
            // Since Exposed is either the same as NonOptionalExposed, or equal to Optional<NonOptionalExposed>,
            // this cast will always succeed.
            return nonOptionalExposed as! Exposed
        }
        set {
            // Setting to nil is taken as an instruction to remove the object from the UserDefaults.
            if let optional = newValue as? AnyOptional, optional.isNil {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }

            // Since we know that the object is not nil, it must be castable to the non-optional type.
            let nonOptionalNewValue = newValue as! NonOptionalExposed

            // Convert the value to a type which can be stored in UserDefaults, and then store it.
            let valueToStore = valueConvertor.toStorage(nonOptionalNewValue)
            UserDefaults.standard.setValue(valueToStore, forKey: key)
        }
    }
}

// MARK: Initialisers

// We expose all the permitted initialisers separately. One drawback to this is that the Optional and non-Optional
// variants of a given type both need the `init(key: String, defaultValue: Exposed)` initialiser declared, the
// bodies of which will be identical.

// The `init(key: String)` initialisers are only declared where Exposed is an Optional type (so the default can be nil).

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
    init(key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .notConverted())
    }

    init(key: String) {
        self.init(key: key, defaultValue: nil)
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

// Note the different parameter name in the following: codingKey vs key. This is reqired since some Codable types
// are also UserDefaultsPrimitive or RawRepresentable. We need a different key to be able to avoid ambiguity.

public extension UserDefaultsBacked where Exposed == NonOptionalExposed,
                                            NonOptionalExposed: Codable,
                                            Stored == Data {
    init(codingKey key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .codable())
    }
}

public extension UserDefaultsBacked where Exposed == NonOptionalExposed?,
                                            NonOptionalExposed: Codable,
                                            Stored == Data {
    init(codingKey key: String, defaultValue: Exposed) {
        self.init(key: key, defaultValue: defaultValue, valueConvertor: .codable())
    }

    init(codingKey key: String) {
        self.init(codingKey: key, defaultValue: nil)
    }
}

/// Any type which can natively be stored in UserDefaults.
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

// Enables a value of a generic type to be compared with nil, by first checking whether it conforms to this protocol.
private protocol AnyOptional {
    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    var isNil: Bool { self == nil }
}
