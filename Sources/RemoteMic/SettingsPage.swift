import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
  case connection
  case mapping
  case permissions

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .connection: return "settings.section.connection_audio"
    case .mapping: return "settings.section.buttons"
    case .permissions: return "settings.section.permissions"
    }
  }

  var systemImage: String {
    switch self {
    case .connection: return "dot.radiowaves.left.and.right"
    case .mapping: return "keyboard"
    case .permissions: return "lock.shield"
    }
  }
}
