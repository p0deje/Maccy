import Foundation
import Defaults

// Raw values are seconds and are persisted, so existing cases must keep their values.
enum HistoryRetention: Int, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case forever = 0
  case oneHour = 3_600
  case eightHours = 28_800
  case oneDay = 86_400
  case sevenDays = 604_800
  case fourteenDays = 1_209_600
  case thirtyDays = 2_592_000

  var id: Self { self }

  var description: String {
    guard self != .forever else {
      return NSLocalizedString("KeepForForever", tableName: "StorageSettings", comment: "")
    }

    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour]
    formatter.unitsStyle = .full
    return formatter.string(from: TimeInterval(rawValue)) ?? ""
  }
}
