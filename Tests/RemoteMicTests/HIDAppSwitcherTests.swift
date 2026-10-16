import CoreGraphics
import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct HIDAppSwitcherTests {
  @Test func shortTVKeepsItsSingleClickActionWithoutOpeningALatchedSession() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "short-tv-owner")

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 100)
    harness.report([], to: monitor)
    harness.scheduler.advance(by: 1_000)

    #expect(harness.output.ordinaryActions == [.appSwitcher])
    #expect(harness.session.isActive == false)
    #expect(harness.output.events == [.action(.appSwitcher)])
  }

  @Test func longTVLatchesUntilOKAndRepeatedReportsDoNotNavigateTwice() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "switcher-owner")

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 549)
    #expect(harness.session.isActive == false)
    #expect(harness.output.events.isEmpty)
    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 1)
    #expect(harness.session.isActive)
    let openedEvents = harness.output.events
    #expect(openedEvents == [.show(1)])
    #expect(harness.session.selectedApplication?.processIdentifier == 22)
    harness.report([], to: monitor)
    #expect(harness.session.isActive)
    #expect(harness.output.events == openedEvents)

    harness.report([.left], to: monitor)
    harness.report([.left], to: monitor)
    harness.scheduler.advance(by: 600)
    #expect(harness.session.selectedApplication?.processIdentifier == 11)
    #expect(harness.output.events.filter { $0 == .select(0) }.count == 1)
    harness.report([], to: monitor)
    harness.report([.right], to: monitor)
    harness.report([], to: monitor)
    #expect(harness.session.selectedApplication?.processIdentifier == 22)
    #expect(harness.output.events.dropFirst(openedEvents.count) == [.select(0), .select(1)])
    harness.report([.ok], to: monitor)
    harness.report([], to: monitor)

    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.dismissCount == 1)
    #expect(harness.output.activatedIdentifiers == [22])
    #expect(harness.output.events.suffix(2) == [.dismiss, .activate(22)])
  }

  @Test func modalPressesIgnoreConfiguredGesturesAndSuppressNativeEdges() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let suppressor = KeyboardEventSuppressor()
    let monitor = harness.makeMonitor(
      fingerprint: "fallback-owner", isSeized: false, suppressor: suppressor)
    harness.settings.setAction(.commandCopy, for: .left, trigger: .doubleClick)
    harness.settings.setAction(.commandPaste, for: .left, trigger: .longPress)
    harness.settings.setAction(.commandCopy, for: .ok, trigger: .doubleClick)
    harness.settings.setAction(.commandPaste, for: .ok, trigger: .longPress)
    harness.openSwitcher(using: monitor)

    harness.report([.left], to: monitor)
    let leftDown = try #require(harness.keyEvent(code: 123, isDown: true))
    #expect(suppressor.handle(type: .keyDown, event: leftDown))
    harness.scheduler.advance(by: 700)
    harness.report([], to: monitor)
    let leftUp = try #require(harness.keyEvent(code: 123, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: leftUp))
    harness.report([.right], to: monitor)
    let rightDown = try #require(harness.keyEvent(code: 124, isDown: true))
    #expect(suppressor.handle(type: .keyDown, event: rightDown))
    harness.report([], to: monitor)
    let rightUp = try #require(harness.keyEvent(code: 124, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: rightUp))
    harness.report([.ok], to: monitor)
    let okDown = try #require(harness.keyEvent(code: 36, isDown: true))
    #expect(suppressor.handle(type: .keyDown, event: okDown))
    harness.report([], to: monitor)
    let okUp = try #require(harness.keyEvent(code: 36, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: okUp))
    harness.scheduler.advance(by: 1_000)

    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.events.filter { $0 == .select(0) }.count == 1)
    #expect(harness.output.events.filter { $0 == .select(1) }.count == 1)
    #expect(harness.output.activatedIdentifiers == [22])
  }

  @Test func anotherButtonCancelsBeforeItsOrdinaryMappingExecutes() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "normal-action-owner")
    harness.settings.setAction(.commandCopy, for: .menu)
    harness.openSwitcher(using: monitor)

    harness.report([.menu], to: monitor)
    harness.report([], to: monitor)

    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions == [.commandCopy])
    let dismissIndex = try #require(harness.output.events.firstIndex(of: .dismiss))
    let actionIndex = try #require(harness.output.events.firstIndex(of: .action(.commandCopy)))
    #expect(dismissIndex < actionIndex)
    #expect(harness.output.activatedIdentifiers.isEmpty)
  }

  @Test func backCancelsWithoutDeletingAndAllNormalMappingsReturnAfterward() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "restored-mappings-owner")
    harness.settings.setAction(.commandCopy, for: .left)
    harness.settings.setAction(.commandPaste, for: .right)
    harness.settings.setAction(.commandReturn, for: .ok)
    harness.settings.setAction(.deleteBackward, for: .back)
    harness.openSwitcher(using: monitor)

    harness.report([.back], to: monitor)
    harness.report([], to: monitor)
    harness.scheduler.advance(by: 1_000)
    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions.isEmpty)
    #expect(harness.output.dismissCount == 1)
    #expect(harness.output.activatedIdentifiers.isEmpty)

    for button in [RemoteButton.left, .right, .ok, .back] {
      harness.report([button], to: monitor)
      harness.report([], to: monitor)
    }
    #expect(
      harness.output.ordinaryActions == [
        .commandCopy, .commandPaste, .commandReturn, .deleteBackward,
      ])
  }

  @Test func otherRemoteCancelsBeforeMappingAndCannotCancelNewOwnersOnStop() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let first = harness.makeMonitor(fingerprint: "first-owner")
    let second = harness.makeMonitor(fingerprint: "second-owner")
    harness.openSwitcher(using: first)

    harness.report([.ok], to: second)
    harness.report([], to: second)
    #expect(harness.session.isActive == false)
    #expect(harness.output.ordinaryActions == [.returnKey])
    let dismissIndex = try #require(harness.output.events.firstIndex(of: .dismiss))
    let actionIndex = try #require(harness.output.events.firstIndex(of: .action(.returnKey)))
    #expect(dismissIndex < actionIndex)
    #expect(harness.output.activatedIdentifiers.isEmpty)

    harness.openSwitcher(using: second)
    first.stop()
    #expect(harness.session.isActive)
    second.disconnectSimulatedDevice()
    #expect(harness.session.isActive == false)
  }

  @Test func anotherRemotesHeldNativeDirectionPreventsOpeningUntilItIsReleased() throws {
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

    harness.report([], to: other)
    let up = try #require(harness.keyEvent(code: 123, isDown: false))
    #expect(suppressor.handle(type: .keyUp, event: up) == false)
    harness.openSwitcher(using: owner)
    #expect(harness.session.isActive)
    #expect(harness.output.events.filter { $0 == .show(1) }.count == 1)
    #expect(harness.output.ordinaryActions.isEmpty)
  }

  @Test func openingCancelsHeldRepeatsAndPendingGesturesWithoutReleaseActions() throws {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "pending-actions-owner")
    harness.settings.setAction(.commandCopy, for: .home)
    harness.settings.setAction(.commandPaste, for: .home, trigger: .longPress)

    harness.report([.tv], to: monitor)
    harness.scheduler.advance(by: 100)
    // Synthetic multi-usage reports exercise state cleanup, not hardware rollover.
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
  }

  @Test(arguments: HIDAppSwitcherCleanup.allCases)
  func cleanupDismissesWithoutActivatingTheSelectedApplication(_ cleanup: HIDAppSwitcherCleanup)
    throws
  {
    let harness = try HIDAppSwitcherHarness()
    defer { harness.close() }
    let monitor = harness.makeMonitor(fingerprint: "cleanup-owner")
    harness.openSwitcher(using: monitor)

    switch cleanup {
    case .stop: monitor.stop()
    case .disconnect: monitor.disconnectSimulatedDevice()
    case .permission:
      harness.output.permissionsGranted = false
      harness.report([.left], to: monitor)
    case .mappingDisabled:
      harness.settings.customMappingEnabled = false
      harness.report([.left], to: monitor)
    }

    #expect(harness.session.isActive == false)
    #expect(harness.output.dismissCount == 1)
    #expect(harness.output.activatedIdentifiers.isEmpty)
    #expect(harness.output.ordinaryActions.isEmpty)
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
  case show(Int)
  case select(Int)
  case dismiss
  case activate(Int32)
  case action(ButtonAction)
}

@MainActor
private final class HIDAppSwitcherOutput {
  var events: [HIDAppSwitcherEvent] = []
  var permissionsGranted = true
  let availableApplications = [Int32(11), 22, 33].map { identifier in
    AppSwitcherApplication(
      processIdentifier: identifier,
      bundleIdentifier: "com.example.hid-switcher.\(identifier)",
      name: "App \(identifier)",
      bundleURL: URL(fileURLWithPath: "/Applications/HIDTestApp\(identifier).app")
    )
  }

  var ordinaryActions: [ButtonAction] {
    events.compactMap { if case .action(let action) = $0 { action } else { nil } }
  }

  var activatedIdentifiers: [Int32] {
    events.compactMap { if case .activate(let identifier) = $0 { identifier } else { nil } }
  }

  var dismissCount: Int {
    events.filter { $0 == .dismiss }.count
  }
}

@MainActor
private final class HIDAppSwitcherPresenter: AppSwitcherPresenting {
  let output: HIDAppSwitcherOutput

  init(output: HIDAppSwitcherOutput) { self.output = output }

  func show(applications: [AppSwitcherApplication], selectedIndex: Int) {
    output.events.append(.show(selectedIndex))
  }

  func select(index: Int) { output.events.append(.select(index)) }

  func dismiss() { output.events.append(.dismiss) }
}

@MainActor
private final class HIDAppSwitcherHarness {
  let suiteName: String
  let defaults: UserDefaults
  let settings: AppSettings
  let scheduler: HIDAppSwitcherManualScheduler
  let output: HIDAppSwitcherOutput
  let presenter: HIDAppSwitcherPresenter
  let session: AppSwitcherSession
  private var monitors: [HIDRemoteMonitor] = []

  init() throws {
    let suiteName = "RemoteMicTests.HIDAppSwitcher.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let settings = AppSettings(defaults: defaults)
    let scheduler = HIDAppSwitcherManualScheduler()
    let output = HIDAppSwitcherOutput()
    let presenter = HIDAppSwitcherPresenter(output: output)
    self.suiteName = suiteName
    self.defaults = defaults
    self.settings = settings
    self.scheduler = scheduler
    self.output = output
    self.presenter = presenter
    settings.customMappingEnabled = true
    session = AppSwitcherSession(
      scheduler: scheduler,
      accessibilityTrusted: { output.permissionsGranted },
      applications: { output.availableApplications },
      activateApplication: { application in
        output.events.append(.activate(application.processIdentifier))
        return true
      },
      presenter: presenter,
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
    report([], to: monitor)
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
