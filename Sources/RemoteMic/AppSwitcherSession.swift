import Foundation

struct AppSwitcherApplication: Equatable {
  let processIdentifier: Int32
  let bundleIdentifier: String
  let name: String
  let bundleURL: URL
}

@MainActor
protocol AppSwitcherPresenting: AnyObject {
  func show(applications: [AppSwitcherApplication], selectedIndex: Int)
  func select(index: Int)
  func dismiss()
}

/// Owns the selection, not a held keyboard modifier. HID input updates it directly.
@MainActor
final class AppSwitcherSession {
  private let scheduler: HIDRemoteScheduling
  private let accessibilityTrusted: () -> Bool
  private let runningApplications: @MainActor () -> [AppSwitcherApplication]
  private let activateApplication: @MainActor (AppSwitcherApplication) -> Bool
  private let presenter: AppSwitcherPresenting
  private let idleTimeoutMilliseconds: UInt64
  private let diagnosticLogger: (String) -> Void
  private var owner: UUID?
  private var pressedButtons: [UUID: Set<RemoteButton>] = [:]
  private var idleTask: HIDRemoteScheduledTask?
  private var timeoutGeneration: UInt64 = 0

  private(set) var applications: [AppSwitcherApplication] = []
  private(set) var selectedIndex = 0
  var selectedApplication: AppSwitcherApplication? {
    applications.indices.contains(selectedIndex) ? applications[selectedIndex] : nil
  }
  var isActive: Bool { owner != nil }

  init(
    scheduler: HIDRemoteScheduling = DispatchHIDRemoteScheduler(),
    accessibilityTrusted: @escaping () -> Bool = { KeyboardInjector.isAccessibilityTrusted },
    applications: @escaping @MainActor () -> [AppSwitcherApplication] = RunningApplicationCatalog
      .snapshot,
    activateApplication: @escaping @MainActor (AppSwitcherApplication) -> Bool =
      RunningApplicationCatalog.activate,
    presenter: AppSwitcherPresenting? = nil,
    idleTimeoutMilliseconds: UInt64 = 30_000,
    diagnosticLogger: @escaping (String) -> Void = AppLogger.shared.write
  ) {
    self.scheduler = scheduler
    self.accessibilityTrusted = accessibilityTrusted
    self.runningApplications = applications
    self.activateApplication = activateApplication
    self.presenter = presenter ?? AppSwitcherPanel()
    self.idleTimeoutMilliseconds = idleTimeoutMilliseconds
    self.diagnosticLogger = diagnosticLogger
  }

  func isOwned(by owner: UUID) -> Bool { self.owner == owner }

  func updatePressedButtons(_ buttons: Set<RemoteButton>, owner: UUID) {
    pressedButtons[owner] = buttons.isEmpty ? nil : buttons
  }

  func canBegin(owner: UUID) -> Bool {
    pressedButtons.keys.allSatisfy { $0 == owner }
  }

  @discardableResult
  func begin(owner: UUID) -> Bool {
    guard canBegin(owner: owner) else {
      diagnosticLogger("APP_SWITCHER rejected reason=another_remote_held")
      return false
    }
    cancel()
    guard accessibilityTrusted() else { return false }
    let candidates = runningApplications()
    guard !candidates.isEmpty else {
      diagnosticLogger("APP_SWITCHER rejected reason=no_applications")
      return false
    }
    applications = candidates
    selectedIndex = candidates.count > 1 ? 1 : 0
    self.owner = owner
    presenter.show(applications: applications, selectedIndex: selectedIndex)
    resetIdleTimeout()
    logSelection("opened")
    return true
  }

  /// Called before normal mappings or native passthrough on every physical press.
  func handlePress(_ button: RemoteButton, owner: UUID) -> Bool {
    guard let currentOwner = self.owner else { return false }
    guard accessibilityTrusted() else {
      cancel()
      return true
    }
    guard currentOwner == owner else {
      cancel()
      return false
    }
    switch button {
    case .left, .right:
      selectedIndex =
        (selectedIndex + (button == .left ? -1 : 1) + applications.count) % applications.count
      presenter.select(index: selectedIndex)
      logSelection("navigate direction=\(button.rawValue)")
      resetIdleTimeout()
    case .ok:
      let target = selectedApplication
      finish()
      let activated = target.map { activateApplication($0) } ?? false
      diagnosticLogger(
        "APP_SWITCHER committed target=\(target?.bundleIdentifier ?? "none") activated=\(activated)"
      )
    case .back:
      cancel()
    case .tv:
      resetIdleTimeout()
    default:
      cancel()
      return false
    }
    return true
  }

  func cancel(owner: UUID? = nil) {
    guard self.owner != nil, owner == nil || self.owner == owner else { return }
    finish()
    diagnosticLogger("APP_SWITCHER cancelled")
  }

  private func finish() {
    idleTask?.cancel()
    idleTask = nil
    timeoutGeneration &+= 1
    owner = nil
    presenter.dismiss()
    applications = []
    selectedIndex = 0
  }

  private func logSelection(_ action: String) {
    diagnosticLogger(
      "APP_SWITCHER \(action) index=\(selectedIndex) count=\(applications.count) target=\(selectedApplication?.bundleIdentifier ?? "none")"
    )
  }

  private func resetIdleTimeout() {
    idleTask?.cancel()
    timeoutGeneration &+= 1
    let generation = timeoutGeneration
    idleTask = scheduler.schedule(
      afterMilliseconds: idleTimeoutMilliseconds,
      repeatingEveryMilliseconds: nil
    ) { [weak self] in
      guard let self, self.timeoutGeneration == generation else { return }
      self.cancel()
    }
  }
}
