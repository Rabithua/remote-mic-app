import AppKit
import Observation
import ServiceManagement

enum LoginItemState: Equatable {
  case disabled
  case enabled
  case requiresApproval
  case failed(String)

  var isEnabled: Bool {
    self == .enabled
  }
}

@MainActor
protocol LoginItemServicing {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

@MainActor
private struct MainAppLoginItemService: LoginItemServicing {
  var status: SMAppService.Status { SMAppService.mainApp.status }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

@MainActor
@Observable
final class LoginItemManager {
  private let service: any LoginItemServicing
  private(set) var state: LoginItemState = .disabled

  init() {
    service = MainAppLoginItemService()
    refresh()
  }

  init(service: any LoginItemServicing) {
    self.service = service
    refresh()
  }

  var isEnabled: Bool { state.isEnabled }

  func refresh() {
    switch service.status {
    case .enabled:
      state = .enabled
    case .requiresApproval:
      state = .requiresApproval
    case .notRegistered, .notFound:
      state = .disabled
    @unknown default:
      state = .disabled
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      refresh()
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}
