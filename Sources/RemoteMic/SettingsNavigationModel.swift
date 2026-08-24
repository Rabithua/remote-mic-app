import Observation

@MainActor
@Observable
final class SettingsNavigationModel {
  var selection: SettingsPage = .connection
}
