import CoreGraphics
import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct HIDAppSwitcherTests {
  @Test func shortTVKeepsItsSingleClickActionWithoutHoldingCommand() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "short-tv-owner")

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 100)
    harness.report([], to: monitor)
    harness.scheduler.advance(by: 1_000)

    #expect(harness.output.ordinaryActions == [.appSwitcher])
    #expect(harness.session.isActive == false)
    #expect(harness.output.keyDownCodes.isEmpty)
  }

  @Test func holdingTVRepeatsTabAndReleasingItCommitsExactlyOnce() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "held-tv-owner")

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 549)
    #expect(harness.session.isActive == false)
    #expect(harness.output.events.isEmpty)
    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 1)
    #expect(harness.session.isActive)
    #expect(
      harness.output.events == [
        .key(55, true, .maskCommand), .key(48, true, .maskCommand),
      ])
    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 20)
    #expect(harness.output.events.last == .key(48, false, .maskCommand))
    harness.scheduler.advance(by: 330)
    #expect(harness.output.events.last == .key(48, true, .maskCommand))
    #expect(harness.output.keyDownCodes.filter { $0 == 48 }.count == 2)
    harness.scheduler.advance(by: 20)
    #expect(harness.output.events.last == .key(48, false, .maskCommand))

    harness.report([], to: monitor)
    harness.report([], to: monitor)

    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.commandReleaseCount == 1)
    #expect(harness.output.events.last == .key(55, false, []))
    #expect(harness.output.keyDownCodes.contains(53) == false)
    let events = harness.output.events
    harness.scheduler.advance(by: 40_000)
    #expect(harness.output.events == events)
  }

  @Test func nativeTVDownAndUpAreSuppressedWhileReleaseCommitsPendingTab() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let suppressor = KeyboardEventSuppressor()
    let monitor = harness.makeMonitor(
      fingerprint: "fallback-tv-owner", isSeized: false, suppressor: suppressor)

    harness.report([.tv], to: monitor)
    let tvDown = try #require(harness.keyEvent(code: 10, isDown: true))
    #expect(suppressor.handle(type: .keyDown, event: tvDown))
    harness.scheduler.advance(by: 550)
    #expect(harness.session.isActive)
    harness.report([], to: monitor)
    let tvUp = try #require(harness.keyEvent(code: 10, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: tvUp))

    #expect(harness.session.isActive == false)
    #expect(
      harness.output.events.suffix(2) == [
        .key(48, false, .maskCommand), .key(55, false, []),
      ])
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.keyDownCodes.contains(53) == false)
  }

  @Test(arguments: [RemoteButton.left, .right, .ok, .menu])
  func otherButtonsCancelBeforeTheirOrdinaryMappings(_ button: RemoteButton) throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "normal-action-owner")
    harness.settings.setAction(.commandCopy, for: button)
    harness.settings.setAction(.disabled, for: button, trigger: .doubleClick)
    harness.settings.setAction(.disabled, for: button, trigger: .longPress)
    harness.openSwitcher(using: monitor)

    // Synthetic overlap tests command cleanup without requiring hardware rollover.
    harness.report([.tv, button], to: monitor)
    harness.report([], to: monitor)

    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions == [.commandCopy])
    #expect(harness.output.keyDownCodes.contains(53))
    let releaseIndex = try #require(harness.output.events.firstIndex(of: .key(55, false, [])))
    let actionIndex = try #require(harness.output.events.firstIndex(of: .action(.commandCopy)))
    #expect(releaseIndex < actionIndex)
  }

  @Test func backCancelsWithoutDeletingAndNormalMappingsReturnAfterward() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "restored-mappings-owner")
    harness.settings.setAction(.commandCopy, for: .left)
    harness.settings.setAction(.commandPaste, for: .right)
    harness.settings.setAction(.commandReturn, for: .ok)
    harness.settings.setAction(.deleteBackward, for: .back)
    harness.openSwitcher(using: monitor)

    harness.report([.tv, .back], to: monitor)
    harness.report([], to: monitor)
    harness.scheduler.advance(by: 1_000)
    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.keyDownCodes.filter { $0 == 53 }.count == 1)
    #expect(harness.output.commandReleaseCount == 1)

    for button in [RemoteButton.left, .right, .ok, .back] {
      harness.report([button], to: monitor)
      harness.report([], to: monitor)
    }
    #expect(
      harness.output.ordinaryActions == [
        .commandCopy, .commandPaste, .commandReturn, .deleteBackward,
      ])
  }

  @Test func otherRemoteCancelsBeforeMappingAndCannotCancelNewOwnerOnStop() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let first = harness.makeMonitor(fingerprint: "first-owner")
    let second = harness.makeMonitor(fingerprint: "second-owner")
    harness.openSwitcher(using: first)

    harness.report([.ok], to: second)
    harness.report([], to: second)
    harness.report([], to: first)
    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions == [.returnKey])
    let releaseIndex = try #require(harness.output.events.firstIndex(of: .key(55, false, [])))
    let actionIndex = try #require(harness.output.events.firstIndex(of: .action(.returnKey)))
    #expect(releaseIndex < actionIndex)

    harness.openSwitcher(using: second)
    first.stop()
    #expect(harness.session.isActive)
    second.disconnectSimulatedDevice()
    #expect(harness.session.isActive == false)
  }

  @Test func anotherRemotesHeldNativeDirectionBlocksOpeningUntilReleased() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let owner = harness.makeMonitor(fingerprint: "waiting-owner")
    let suppressor = KeyboardEventSuppressor()
    let other = harness.makeMonitor(
      fingerprint: "native-held-owner", isSeized: false, suppressor: suppressor)

    harness.report([.left], to: other)
    let down = try #require(harness.keyEvent(code: 123, isDown: true))
    #expect(suppressor.handle(type: .keyDown, event: down) == false)
    harness.openSwitcher(using: owner)
    #expect(harness.session.isActive == false)
    #expect(harness.output.events.isEmpty)
    harness.report([], to: owner)

    harness.report([], to: other)
    let up = try #require(harness.keyEvent(code: 123, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: up) == false)
    harness.openSwitcher(using: owner)
    #expect(harness.session.isActive)
    #expect(harness.output.keyDownCodes.filter { $0 == 55 }.count == 1)
    #expect(harness.output.ordinaryActions.isEmpty)
    harness.report([], to: owner)
    #expect(harness.session.isActive == false)
  }

  @Test func openingCancelsHeldRepeatsAndPendingGesturesWithoutReleaseActions() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "pending-actions-owner")
    harness.settings.setAction(.commandCopy, for: .home)
    harness.settings.setAction(.commandPaste, for: .home, trigger: .longPress)

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 100)
    harness.report([.tv, .home, .volumeUp], to: monitor)
    harness.scheduler.advance(by: 450)
    #expect(harness.session.isActive)
    let actionsAtOpening = harness.output.ordinaryActions
    harness.scheduler.advance(by: 2_000)
    harness.report([], to: monitor)
    harness.scheduler.advance(by: 1_000)

    #expect(harness.output.ordinaryActions == actionsAtOpening)
    #expect(harness.output.ordinaryActions.contains(.commandCopy) == false)
    #expect(harness.output.ordinaryActions.contains(.commandPaste) == false)
    #expect(harness.session.isActive == false)
    #expect(harness.output.keyDownCodes.contains(53) == false)
  }

  @Test(arguments: HIDAppSwitcherCleanup.allCases)
  func cleanupCancelsInsteadOfCommitting(_ cleanup: HIDAppSwitcherCleanup) throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "cleanup-owner")
    harness.openSwitcher(using: monitor)

    switch cleanup {
    case .stop: monitor.stop()
    case .disconnect: monitor.disconnectSimulatedDevice()
    case .permission:
      harness.output.permissionsGranted = false
      harness.report([.tv], to: monitor)
    case .mappingDisabled:
      harness.settings.customMappingEnabled = false
      harness.report([.tv], to: monitor)
    }

    #expect(harness.session.isActive == false)
    #expect(harness.output.commandReleaseCount == 1)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(
      harness.output.events.suffix(4) == [
        .key(48, false, .maskCommand), .key(53, true, .maskCommand),
        .key(53, false, .maskCommand), .key(55, false, []),
      ])
    let events = harness.output.events
    harness.scheduler.advance(by: 40_000)
    #expect(harness.output.events == events)
  }

  @Test(arguments: [ButtonTrigger.singleClick, .doubleClick])
  func browseActionAfterTheButtonReleaseFallsBackToOneNormalSwitch(
    _ trigger: ButtonTrigger
  ) throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "released-action-owner")
    harness.settings.setAction(.disabled, for: .tv, trigger: .longPress)
    if trigger == .singleClick {
      harness.settings.setAction(.browseApps, for: .tv)
      harness.settings.setAction(.commandCopy, for: .tv, trigger: .doubleClick)
    } else {
      harness.settings.setAction(.browseApps, for: .tv, trigger: .doubleClick)
    }

    harness.report([.tv], to: monitor)
    harness.report([], to: monitor)
    if trigger == .doubleClick {
      harness.scheduler.advance(by: 100)
      harness.report([.tv], to: monitor)
      harness.report([], to: monitor)
    }
    harness.scheduler.advance(by: 1_000)

    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions == [.appSwitcher])
    #expect(harness.output.keyDownCodes.isEmpty)
  }

  @Test func browseActionOnAnotherHeldButtonCommitsOnThatButtonsRelease() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "home-initiator-owner")
    harness.settings.setAction(.commandCopy, for: .home)
    harness.settings.setAction(.browseApps, for: .home, trigger: .longPress)

    harness.report([.home], to: monitor)
    harness.scheduler.advance(by: 550)
    #expect(harness.session.isActive)
    harness.report([], to: monitor)
    #expect(harness.session.isActive == false)
    #expect(harness.output.commandReleaseCount == 1)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.keyDownCodes.contains(53) == false)
  }

  @Test func aCustomTVLongPressAndOrdinaryDirectionPassthroughRemainIntact() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let suppressor = KeyboardEventSuppressor()
    let monitor = harness.makeMonitor(
      fingerprint: "custom-tv-owner", isSeized: false, suppressor: suppressor)
    harness.settings.setAction(.commandPaste, for: .tv, trigger: .longPress)

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 550)
    harness.report([], to: monitor)
    #expect(harness.output.ordinaryActions == [.commandPaste])
    #expect(harness.session.isActive == false)

    harness.report([.left], to: monitor)
    let down = try #require(harness.keyEvent(code: 123, isDown: true))
    #expect(suppressor.handle(type: .keyDown, event: down) == false)
    harness.report([], to: monitor)
    let up = try #require(harness.keyEvent(code: 123, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: up) == false)
    #expect(harness.output.ordinaryActions == [.commandPaste])
  }
}

enum HIDAppSwitcherCleanup: CaseIterable {
  case stop, disconnect, permission, mappingDisabled
}

private enum HIDAppSwitcherEvent: Equatable {
  case key(CGKeyCode, Bool, CGEventFlags)
  case action(ButtonAction)
}

@MainActor
private final class HIDAppSwitcherOutput {
  var events: [HIDAppSwitcherEvent] = []
  var permissionsGranted = true

  var ordinaryActions: [ButtonAction] {
    events.compactMap { if case .action(let action) = $0 { action } else { nil } }
  }

  var keyDownCodes: [CGKeyCode] {
    events.compactMap { if case .key(let code, true, _) = $0 { code } else { nil } }
  }

  var commandReleaseCount: Int {
    events.filter { $0 == .key(55, false, []) }.count
  }
}

@MainActor
private final class HIDAppSwitcherHarness {
  let suiteName: String
  let defaults: UserDefaults
  let settings: AppSettings
  let scheduler: HIDAppSwitcherManualScheduler
  let output: HIDAppSwitcherOutput
  let session: AppSwitcherSession
  private var monitors: [HIDRemoteMonitor] = []

  init() throws {
    let suiteName = "RemoteMicTests.HIDAppSwitcher.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let settings = AppSettings(defaults: defaults)
    let scheduler = HIDAppSwitcherManualScheduler()
    let output = HIDAppSwitcherOutput()
    self.suiteName = suiteName
    self.defaults = defaults
    self.settings = settings
    self.scheduler = scheduler
    self.output = output
    settings.customMappingEnabled = true
    session = AppSwitcherSession(
      scheduler: scheduler,
      accessibilityTrusted: { output.permissionsGranted },
      postKeyState: { code, isDown, flags in
        output.events.append(.key(code, isDown, flags))
        return true
      },
      diagnosticLogger: { _ in }
    )
  }

  func makeMonitor(
    fingerprint: String,
    isSeized: Bool = true,
    suppressor: KeyboardEventSuppressor = KeyboardEventSuppressor()
  ) -> HIDRemoteMonitor {
    let profileID = settings.registerHIDRemote(fingerprint: fingerprint)
    settings.selectRemoteProfile(profileID)
    settings.setAction(.appSwitcher, for: .tv)
    settings.setAction(.browseApps, for: .tv, trigger: .longPress)
    let output = output
    let monitor = HIDRemoteMonitor(
      settings: settings,
      profileID: profileID,
      eventSuppressor: suppressor,
      appSwitcher: session,
      scheduler: scheduler,
      runtimePermissions: { output.permissionsGranted },
      actionPerformer: { _, _, configured in
        output.events.append(.action(configured.action))
        return true
      },
      frontmostBundleIdentifier: { "com.example.foreground" },
      diagnosticLogger: { _ in }
    )
    monitor.connectSimulatedDevice(
      fingerprint: fingerprint, profileID: profileID, isSeized: isSeized)
    monitors.append(monitor)
    return monitor
  }

  func report(_ buttons: [RemoteButton], to monitor: HIDRemoteMonitor) {
    let usages = buttons.isEmpty ? [UInt16(0)] : buttons.map(\.hidUsage)
    let bytes = usages.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    monitor.handleSimulatedReport(reportID: 1, data: Data(bytes))
  }

  func openSwitcher(using monitor: HIDRemoteMonitor) {
    report([.tv], to: monitor)
    scheduler.advance(by: 550)
  }

  func keyEvent(code: CGKeyCode, isDown: Bool) -> CGEvent? {
    CGEvent(
      keyboardEventSource: nil,
      virtualKey: code,
      keyDown: isDown
    )
  }

  func close() {
    for monitor in monitors { monitor.stop() }
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private final class HIDAppSwitcherManualTask: HIDRemoteScheduledTask {
  let id: Int
  var dueAt: UInt64
  let interval: UInt64?
  let action: () -> Void
  var cancelled = false

  init(id: Int, dueAt: UInt64, interval: UInt64?, action: @escaping () -> Void) {
    self.id = id
    self.dueAt = dueAt
    self.interval = interval
    self.action = action
  }

  func cancel() { cancelled = true }
}

private final class HIDAppSwitcherManualScheduler: HIDRemoteScheduling {
  private var now: UInt64 = 0
  private var nextID = 0
  private var tasks: [HIDAppSwitcherManualTask] = []

  func schedule(
    afterMilliseconds: UInt64,
    repeatingEveryMilliseconds: UInt64?,
    _ action: @escaping () -> Void
  ) -> HIDRemoteScheduledTask {
    nextID += 1
    let task = HIDAppSwitcherManualTask(
      id: nextID,
      dueAt: now + afterMilliseconds,
      interval: repeatingEveryMilliseconds,
      action: action
    )
    tasks.append(task)
    return task
  }

  func advance(by milliseconds: UInt64) {
    let target = now + milliseconds
    while let task = tasks.filter({ !$0.cancelled && $0.dueAt <= target })
      .min(by: { ($0.dueAt, $0.id) < ($1.dueAt, $1.id) })
    {
      now = task.dueAt
      if let interval = task.interval {
        task.dueAt += interval
      } else {
        task.cancelled = true
      }
      task.action()
    }
    tasks.removeAll { $0.cancelled }
    now = target
  }
}
