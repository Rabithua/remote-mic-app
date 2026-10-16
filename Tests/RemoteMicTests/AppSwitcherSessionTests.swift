import CoreGraphics
import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct AppSwitcherSessionTests {
  @Test func holdsCommandThroughNavigationAndReleasesOnlyOnConfirmation() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.events == [.commandDown, .down(48), .up(48)])
    #expect(fixture.session.isOwned(by: owner))
    #expect(fixture.session.handlePress(.tv, owner: owner))
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.handlePress(.left, owner: owner))
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.isActive)
    #expect(
      fixture.events.suffix(6) == [
        .down(48), .up(48),
        .down(48, flags: [.maskCommand, .maskShift]),
        .up(48, flags: [.maskCommand, .maskShift]),
        .down(48), .up(48),
      ])

    #expect(fixture.session.handlePress(.ok, owner: owner))
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.last == .commandUp)
    #expect(fixture.events.contains(.down(53)) == false)
    let count = fixture.events.count
    fixture.session.cancel()
    #expect(fixture.events.count == count)
  }

  @Test func backCancelsBeforeReleasingCommand() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.back, owner: owner))
    #expect(fixture.events.suffix(3) == [.down(53), .up(53), .commandUp])
    #expect(fixture.session.isActive == false)
  }

  @Test func unrelatedInputAndAnotherRemoteCannotInheritHeldCommand() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.handlePress(.left, owner: owner) == false)
    #expect(fixture.events.isEmpty)
    #expect(fixture.session.begin(owner: owner))
    fixture.session.cancel(owner: UUID())
    #expect(fixture.session.isActive)

    #expect(fixture.session.handlePress(.ok, owner: UUID()) == false)
    #expect(fixture.events.suffix(3) == [.down(53), .up(53), .commandUp])
    #expect(fixture.session.isActive == false)

    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.volumeUp, owner: owner) == false)
    #expect(fixture.events.last == .commandUp)
    #expect(fixture.session.isActive == false)
  }

  @Test func onlyTheCurrentIdleTimerCanCancelTheSession() throws {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    let oldTimer = try #require(fixture.scheduler.tasks.first)
    #expect(oldTimer.delay == 30_000)
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(oldTimer.cancelled)
    oldTimer.action()
    #expect(fixture.session.isActive)
    let currentTimer = try #require(fixture.scheduler.tasks.last)
    currentTimer.action()
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.suffix(3) == [.down(53), .up(53), .commandUp])
    let count = fixture.events.count
    currentTimer.action()
    #expect(fixture.events.count == count)
  }

  @Test func missingOrRevokedPermissionFailsClosedButStillAttemptsCleanup() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    fixture.trusted = false
    #expect(fixture.session.begin(owner: owner) == false)
    #expect(fixture.events.isEmpty)
    fixture.trusted = true
    #expect(fixture.session.begin(owner: owner))
    fixture.trusted = false
    #expect(fixture.session.handlePress(.left, owner: owner))
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.suffix(3) == [.down(53), .up(53), .commandUp])
  }

  @Test(arguments: SwitcherFailureStage.allCases)
  func injectionFailureAlwaysReleasesTheModifier(stage: SwitcherFailureStage) {
    let fixture = SwitcherFixture()
    let owner = UUID()
    if stage != .navigationTab {
      fixture.failedDownKey = stage == .command ? 55 : 48
    }
    let opened = fixture.session.begin(owner: owner)
    if stage == .navigationTab {
      #expect(opened)
      fixture.failedDownKey = 48
      #expect(fixture.session.handlePress(.right, owner: owner))
    } else {
      #expect(opened == false)
    }
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.last == .commandUp)
  }

  @Test func reopeningCancelsPreviousSelectionBeforeStartingAnother() {
    let fixture = SwitcherFixture()
    #expect(fixture.session.begin(owner: UUID()))
    let nextOwner = UUID()
    #expect(fixture.session.begin(owner: nextOwner))
    #expect(
      fixture.events.suffix(6) == [
        .down(53), .up(53), .commandUp, .commandDown, .down(48), .up(48),
      ])
    #expect(fixture.session.isOwned(by: nextOwner))
    fixture.session.cancel(owner: nextOwner)
    #expect(fixture.session.isActive == false)
  }

  @Test func anotherRemotesHeldInputBlocksOpeningUntilItIsReleased() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    let other = UUID()
    fixture.session.updatePressedButtons([.tv], owner: owner)
    fixture.session.updatePressedButtons([.left], owner: other)
    #expect(fixture.session.canBegin(owner: owner) == false)
    #expect(fixture.session.begin(owner: owner) == false)
    #expect(fixture.events.isEmpty)
    fixture.session.updatePressedButtons([], owner: other)
    #expect(fixture.session.canBegin(owner: owner))
    #expect(fixture.session.begin(owner: owner))
    fixture.session.cancel()
  }
}

enum SwitcherFailureStage: CaseIterable {
  case command, openingTab, navigationTab
}

private struct SwitcherKeyEvent: Equatable {
  let code: CGKeyCode
  let isDown: Bool
  let flags: CGEventFlags

  static let commandDown = Self(code: 55, isDown: true, flags: .maskCommand)
  static let commandUp = Self(code: 55, isDown: false, flags: [])
  static func down(_ code: CGKeyCode, flags: CGEventFlags = .maskCommand) -> Self {
    Self(code: code, isDown: true, flags: flags)
  }
  static func up(_ code: CGKeyCode, flags: CGEventFlags = .maskCommand) -> Self {
    Self(code: code, isDown: false, flags: flags)
  }
}

@MainActor
private final class SwitcherFixture {
  var trusted = true
  var failedDownKey: CGKeyCode?
  var events: [SwitcherKeyEvent] = []
  let scheduler = SwitcherTestScheduler()
  lazy var session = AppSwitcherSession(
    scheduler: scheduler,
    accessibilityTrusted: { [unowned self] in trusted },
    postKeyState: { [unowned self] code, isDown, flags in
      events.append(SwitcherKeyEvent(code: code, isDown: isDown, flags: flags))
      return !(isDown && code == failedDownKey)
    },
    diagnosticLogger: { _ in }
  )
}

private final class SwitcherTestTask: HIDRemoteScheduledTask {
  let delay: UInt64
  let action: () -> Void
  var cancelled = false
  init(delay: UInt64, action: @escaping () -> Void) {
    self.delay = delay
    self.action = action
  }
  func cancel() { cancelled = true }
}

private final class SwitcherTestScheduler: HIDRemoteScheduling {
  var tasks: [SwitcherTestTask] = []
  func schedule(
    afterMilliseconds: UInt64,
    repeatingEveryMilliseconds: UInt64?,
    _ action: @escaping () -> Void
  ) -> HIDRemoteScheduledTask {
    let task = SwitcherTestTask(delay: afterMilliseconds, action: action)
    tasks.append(task)
    return task
  }
}
