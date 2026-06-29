import CoreGraphics
import Defaults
import Foundation

/// Conformance enabling `NSPoint` to be persisted via the Defaults wrapper.
extension NSPoint: Defaults.Serializable {
}
