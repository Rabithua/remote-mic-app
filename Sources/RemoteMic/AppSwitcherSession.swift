import CoreGraphics
import Foundation

/// Owns the synthetic Command key for one remote's latched system app switcher.
@MainActor
final class AppSwitcherSession {
  private let scheduler: HIDRemoteScheduling
  private let accessibilityTrusted: () -> Bool
  private let postKeyState: (CGKeyCode, Bool, CGEventFlags) -> Bool
  private let idleTimeoutMilliseconds: UInt64
  private let diagnosticLogger: (String) -> Void
  private var owner: UUID?
  private var pressedButtons: [UUID: Set<RemoteButton>] = [:]
  private var idleTask: HIDRemoteScheduledTask?
  private var timeoutGeneration: UInt64 = 0

  var isActive: Bool { owner != nil }

  init(
    scheduler: HIDRemoteScheduling = DispatchHIDRemoteScheduler(),
    accessibilityTrusted: @escaping () -> Bool = { KeyboardInjector.isAccessibilityTrusted },
    postKeyState: @escaping (CGKeyCode, Bool, CGEventFlags) -> Bool =
      KeyboardInjector.postAppSwitcherKeyState,
    idleTimeoutMilliseconds: UInt64 = 30_000,
    diagnosticLogger: @escaping (String) -> Void = AppLogger.shared.write
  ) {
    self.scheduler = scheduler
    self.accessibilityTrusted = accessibilityTrusted
    self.postKeyState = postKeyState
    self.idleTimeoutMilliseconds = idleTimeoutMilliseconds
    self.diagnosticLogger = diagnosticLogger
  }

  func isOwned(by owner: UUID) -> Bool { self.owner == owner }

  func updatePressedButtons(_ buttons: Set<RemoteButton>, owner: UUID) {
    pressedButtons[owner] = buttons.isEmpty ? nil : buttons
  }

  func canBegin(owner: UUID) -> Bool {
    // A native held key on another remote can repeat without another HID edge.
    // Do not hold Command until that input has been released.
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
    guard postKeyState(55, true, .maskCommand) else {
      // Best-effort release is deliberately not gated by permission checks.
      _ = postKeyState(55, false, [])
      return false
    }
    self.owner = owner
    guard pressAndRelease(48) else {
      cancel()
      return false
    }
    resetIdleTimeout()
    diagnosticLogger("APP_SWITCHER opened")
    return true
  }

  /// Called before normal mappings or native passthrough on every physical press.
  /// Unrelated input first cancels this session, so it cannot inherit our Command.
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
      // Use the native forward/backward shortcuts, reusing the Tab path that
      // opens the switcher, rather than synthesizing arrow keys.
      let flags: CGEventFlags = button == .left ? [.maskCommand, .maskShift] : .maskCommand
      let posted = pressAndRelease(48, flags: flags)
      diagnosticLogger(
        "APP_SWITCHER navigate direction=\(button.rawValue) method=\(button == .left ? "shift_tab" : "tab") posted=\(posted)"
      )
      if posted {
        resetIdleTimeout()
      } else {
        cancel()
      }
    case .ok:
      finish(cancelled: false)
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
    finish(cancelled: true)
  }

  private func pressAndRelease(_ keyCode: CGKeyCode, flags: CGEventFlags = .maskCommand) -> Bool {
    let pressed = postKeyState(keyCode, true, flags)
    let released = postKeyState(keyCode, false, flags)
    return pressed && released
  }

  private func finish(cancelled: Bool) {
    idleTask?.cancel()
    idleTask = nil
    timeoutGeneration &+= 1
    owner = nil
    if cancelled { _ = pressAndRelease(53) }
    _ = postKeyState(55, false, [])
    diagnosticLogger("APP_SWITCHER \(cancelled ? "cancelled" : "committed")")
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
