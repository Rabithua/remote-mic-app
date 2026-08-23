import ServiceManagement
import Testing

@testable import RemoteMic

@Suite("Login item", .serialized)
@MainActor
struct LoginItemManagerTests {
  @Test func enabledAndDisabledStatesFollowTheSystemService() {
    let service = FakeLoginItemService(status: .notRegistered)
    let manager = LoginItemManager(service: service)
    #expect(!manager.isEnabled)

    manager.setEnabled(true)
    #expect(manager.state == .enabled)
    #expect(manager.isEnabled)

    manager.setEnabled(false)
    #expect(manager.state == .disabled)
    #expect(!manager.isEnabled)
  }

  @Test func approvalRequiredRollsBackTheVisibleSwitch() {
    let service = FakeLoginItemService(status: .notRegistered)
    service.registeredStatus = .requiresApproval
    let manager = LoginItemManager(service: service)

    manager.setEnabled(true)

    #expect(manager.state == .requiresApproval)
    #expect(!manager.isEnabled)
  }

  @Test func registrationErrorRollsBackTheVisibleSwitch() {
    let service = FakeLoginItemService(status: .notRegistered)
    service.registerError = LoginItemTestError.registrationFailed
    let manager = LoginItemManager(service: service)

    manager.setEnabled(true)

    guard case .failed = manager.state else {
      Issue.record("Expected failed state")
      return
    }
    #expect(!manager.isEnabled)
  }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
  var status: SMAppService.Status
  var registeredStatus: SMAppService.Status = .enabled
  var registerError: Error?

  init(status: SMAppService.Status) {
    self.status = status
  }

  func register() throws {
    if let registerError { throw registerError }
    status = registeredStatus
  }

  func unregister() throws {
    status = .notRegistered
  }
}

private enum LoginItemTestError: Error {
  case registrationFailed
}
