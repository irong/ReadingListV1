import Foundation

@propertyWrapper public struct UserDefaultsBacked<Value: Codable> {
    let key: String
    let defaultValue: Value

    public init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Value {
        get {
            guard let storedValue = UserDefaults.standard.value(forKey: key) else { return defaultValue }
            if let typedValue = storedValue as? Value {
                return typedValue
            }
            if let data = storedValue as? Data {
                // For iOS 12 compatibility, decode into arrays containing one item
                return try! JSONDecoder().decode([Value].self, from: data).first!
            }
            assertionFailure("Unexpected UserDefaults stored value")
            return defaultValue
        }
        set {
            if let optional = newValue as? AnyOptional, optional.isNil {
                UserDefaults.standard.removeObject(forKey: key)
            } else if newValue is UserDefaultsPrimitive {
                UserDefaults.standard.setValue(newValue, forKey: key)
            } else {
                // For iOS 12 compatibility, encode arrays containing one items
                let encoded = try! JSONEncoder().encode([newValue])
                UserDefaults.standard.setValue(encoded, forKey: key)
            }
        }
    }
}

public extension UserDefaultsBacked where Value: ExpressibleByNilLiteral {
    init(key: String) {
        self.init(key: key, defaultValue: nil)
    }
}

private protocol UserDefaultsPrimitive {}
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
