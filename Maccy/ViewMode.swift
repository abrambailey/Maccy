import Defaults
import Foundation

enum ViewMode: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case list
  case filmstrip

  var id: Self { self }

  var description: String {
    switch self {
    case .list:
      return NSLocalizedString("List", tableName: "AppearanceSettings", comment: "")
    case .filmstrip:
      return NSLocalizedString("Filmstrip", tableName: "AppearanceSettings", comment: "")
    }
  }
}
