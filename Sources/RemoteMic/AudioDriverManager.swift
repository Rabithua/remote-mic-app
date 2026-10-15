import Foundation
import Observation

enum AudioDriverStatus: Equatable, Sendable {
  case checking
  case missing
  case needsRepair
  case conflict
  case ready
  case unavailable

  var canInstall: Bool { self == .missing || self == .needsRepair }

  var messageKey: String {
    switch self {
    case .checking: return "device_setup.driver.checking"
    case .missing: return "device_setup.driver.missing"
    case .needsRepair: return "device_setup.driver.needs_repair"
    case .conflict: return "device_setup.driver.conflict"
    case .ready: return "device_setup.driver.ready"
    case .unavailable: return "device_setup.driver.unavailable"
    }
  }
}

protocol AudioDriverServicing: Sendable {
  func status() async -> AudioDriverStatus
  func install() async throws
}

@MainActor
@Observable
final class AudioDriverManager {
  private(set) var status: AudioDriverStatus = .checking
  private(set) var isInstalling = false
  private(set) var message: LocalizedMessage?
  private let service: any AudioDriverServicing
  private var refreshGeneration = 0

  init(service: any AudioDriverServicing = BundledAudioDriverService()) {
    self.service = service
  }

  func refresh() async {
    guard !isInstalling else { return }
    refreshGeneration += 1
    let generation = refreshGeneration
    let latest = await service.status()
    guard !isInstalling, generation == refreshGeneration else { return }
    if latest != status { message = nil }
    status = latest
  }

  @discardableResult
  func install() async -> Bool {
    guard !isInstalling, status.canInstall else { return false }
    refreshGeneration += 1
    isInstalling = true
    message = LocalizedMessage("device_setup.driver.installing")
    defer { isInstalling = false }
    do {
      try await service.install()
      status = await service.status()
      guard status == .ready else {
        message = LocalizedMessage("device_setup.driver.failed")
        return false
      }
      message = LocalizedMessage("device_setup.driver.installed")
      return true
    } catch is CancellationError {
      message = LocalizedMessage("device_setup.driver.cancelled")
    } catch {
      AppLogger.shared.write("DRIVER INSTALL failed error=\(error.localizedDescription)")
      status = await service.status()
      message = LocalizedMessage("device_setup.driver.failed")
    }
    return false
  }
}
