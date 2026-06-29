import CoreGraphics
import Defaults
import Foundation

/// Conformance enabling `NSSize` to be persisted via the Defaults wrapper.
extension NSSize: Defaults.Serializable {
}
