import Foundation
import Eureka

@discardableResult
public func <<< (left: Section, right: [BaseRow]) -> Section {
    left.append(contentsOf: right)
    return left
}
