import Observation

/// System Bluetooth owns first pairing. Automatic CoreBluetooth connections stay
/// suspended until the user explicitly resumes, even if the app regains focus.
@MainActor
@Observable
final class SystemBluetoothPairingCoordinator {
  private(set) var isActive = false
  private let suspendConnections: () -> Void
  private let resumeConnections: () -> Void
  private let openSettings: () -> Bool

  init(
    suspendConnections: @escaping () -> Void,
    resumeConnections: @escaping () -> Void,
    openSettings: @escaping () -> Bool
  ) {
    self.suspendConnections = suspendConnections
    self.resumeConnections = resumeConnections
    self.openSettings = openSettings
  }

  @discardableResult
  func begin() -> Bool {
    let wasActive = isActive
    if !isActive {
      isActive = true
      suspendConnections()
    }
    guard openSettings() else {
      if !wasActive { resume() }
      return false
    }
    return true
  }

  func resume() {
    guard isActive else { return }
    isActive = false
    resumeConnections()
  }
}
