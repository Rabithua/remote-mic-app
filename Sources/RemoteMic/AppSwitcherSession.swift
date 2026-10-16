import CoreGraphics
import Foundation

/// Holds Command only while the initiating remote button is physically held.
@MainActor
final class AppSwitcherSession {
  private let scheduler: HIDRemoteScheduling
  private let accessibilityTrusted: () -> Bool
  private let postKeyState: (CGKeyCode, Bool, CGEventFlags) -> Bool
  private let idleTimeoutMilliseconds: UInt64
  private let diagnosticLogger: (String) -> Void
  private var owner: UUID?
  private var initiatingButton: RemoteButton?
  private var pressedButtons: [UUID: Set<RemoteButton>] = [:]
  private var repeatTask: HIDRemoteScheduledTask?
  private var tabReleaseTask: HIDRemoteScheduledTask?
  private var idleTask: HIDRemoteScheduledTask?
  private var tabIsDown = false
  private var generation: UInt64 = 0

  static let repeatMilliseconds: UInt64 = 350
  static let keyPressMilliseconds: UInt64 = 20
  var isActive: Bool { owner != nil }

  init(
    scheduler: HIDRemoteScheduling = DispatchHIDRemoteScheduler(),
    accessibilityTrusted: @escaping () -> Bool = { KeyboardInjector.isAccessibilityTrusted },
    postKeyState: ((CGKeyCode, Bool, CGEventFlags) -> Bool)? = nil,
    idleTimeoutMilliseconds: UInt64 = 30_000,
    diagnosticLogger: @escaping (String) -> Void = AppLogger.shared.write
  ) {
    self.scheduler = scheduler
    self.accessibilityTrusted = accessibilityTrusted
    self.postKeyState = postKeyState ?? KeyboardInjector.makeAppSwitcherKeyPoster()
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
  func begin(owner: UUID, button: RemoteButton = .tv) -> Bool {
    guard canBegin(owner: owner) else {
      diagnosticLogger("APP_SWITCHER rejected reason=another_remote_held")
      return false
    }
    cancel()
    guard accessibilityTrusted() else { return false }
    guard postKeyState(55, true, .maskCommand) else {
      _ = postKeyState(55, false, [])
      return false
    }
    self.owner = owner
    initiatingButton = button
    generation &+= 1
    let token = generation
    guard pressTab() else { return false }
    repeatTask = scheduler.schedule(
      afterMilliseconds: Self.repeatMilliseconds,
      repeatingEveryMilliseconds: Self.repeatMilliseconds
    ) { [weak self] in
      guard let self, self.isActive, self.generation == token else { return }
      guard self.accessibilityTrusted() else {
        self.cancel()
        return
      }
      if self.pressTab() { self.diagnosticLogger("APP_SWITCHER advanced method=held_tab") }
    }
    // A lost HID release must not leave a modifier held forever. Repeats do not
    // extend this deadline; only a fresh physical press can start a new session.
    idleTask = scheduler.schedule(
      afterMilliseconds: idleTimeoutMilliseconds, repeatingEveryMilliseconds: nil
    ) { [weak self] in
      guard let self, self.generation == token else { return }
      self.cancel()
    }
    diagnosticLogger("APP_SWITCHER opened mode=hold button=\(button.rawValue)")
    return true
  }

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
    if button == initiatingButton { return true }
    if button == .back {
      cancel()
      return true
    }
    // Cancel before an unrelated mapping executes, so it cannot inherit Command.
    cancel()
    return false
  }

  @discardableResult
  func handleRelease(_ button: RemoteButton, owner: UUID) -> Bool {
    guard self.owner == owner, initiatingButton == button else { return false }
    finish(cancelled: !accessibilityTrusted())
    return true
  }

  func cancel(owner: UUID? = nil) {
    guard self.owner != nil, owner == nil || self.owner == owner else { return }
    finish(cancelled: true)
  }

  private func pressTab() -> Bool {
    guard !tabIsDown else { return true }
    tabIsDown = true
    guard postKeyState(48, true, .maskCommand) else {
      cancel()
      return false
    }
    let token = generation
    tabReleaseTask = scheduler.schedule(
      afterMilliseconds: Self.keyPressMilliseconds, repeatingEveryMilliseconds: nil
    ) { [weak self] in
      guard let self, self.isActive, self.generation == token else { return }
      self.tabReleaseTask = nil
      guard self.postKeyState(48, false, .maskCommand) else {
        self.cancel()
        return
      }
      self.tabIsDown = false
    }
    return true
  }

  private func finish(cancelled: Bool) {
    repeatTask?.cancel()
    tabReleaseTask?.cancel()
    idleTask?.cancel()
    repeatTask = nil
    tabReleaseTask = nil
    idleTask = nil
    generation &+= 1
    owner = nil
    initiatingButton = nil
    if tabIsDown { _ = postKeyState(48, false, .maskCommand) }
    tabIsDown = false
    if cancelled {
      _ = postKeyState(53, true, .maskCommand)
      _ = postKeyState(53, false, .maskCommand)
    }
    _ = postKeyState(55, false, [])
    diagnosticLogger("APP_SWITCHER \(cancelled ? "cancelled" : "committed")")
  }
}
