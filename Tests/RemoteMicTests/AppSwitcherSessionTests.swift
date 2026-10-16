import CoreGraphics
import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct AppSwitcherSessionTests {
  @Test func holdingTVRepeatsTabAndReleasingTVCommitsWithoutEscape() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.events == [.commandDown, .down(48)])
    #expect(fixture.session.isOwned(by: owner))

    fixture.scheduler.advance(by: 19)
    #expect(fixture.events == [.commandDown, .down(48)])
    fixture.scheduler.advance(by: 1)
    #expect(fixture.events == [.commandDown, .down(48), .up(48)])
    #expect(fixture.session.handlePress(.tv, owner: owner))
    #expect(fixture.events.count == 3)
    fixture.scheduler.advance(by: 329)
    #expect(fixture.events.count == 3)
    fixture.scheduler.advance(by: 1)
    #expect(fixture.events.last == .down(48))
    fixture.scheduler.advance(by: 20)
    #expect(fixture.events.suffix(2) == [.down(48), .up(48)])
    #expect(fixture.session.isActive)

    #expect(fixture.session.handleRelease(.tv, owner: owner))
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.last == .commandUp)
    #expect(fixture.events.contains(.down(53)) == false)
    let count = fixture.events.count
    fixture.scheduler.advance(by: 40_000)
    #expect(fixture.events.count == count)
  }

  @Test func releaseDuringPendingTabUpReleasesTabBeforeCommand() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handleRelease(.left, owner: owner) == false)
    #expect(fixture.session.handleRelease(.tv, owner: UUID()) == false)
    #expect(fixture.session.isActive)
    #expect(fixture.events == [.commandDown, .down(48)])

    #expect(fixture.session.handleRelease(.tv, owner: owner))
    #expect(fixture.events == [.commandDown, .down(48), .up(48), .commandUp])
    #expect(fixture.session.handleRelease(.tv, owner: owner) == false)
    let count = fixture.events.count
    fixture.scheduler.advance(by: 1_000)
    #expect(fixture.events.count == count)
  }

  @Test func onlyTheInitiatingButtonReleaseCanCommit() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner, button: .home))
    #expect(fixture.session.handlePress(.home, owner: owner))
    #expect(fixture.session.handleRelease(.tv, owner: owner) == false)
    #expect(fixture.session.isActive)
    #expect(fixture.session.handleRelease(.home, owner: owner))
    #expect(fixture.events.suffix(2) == [.up(48), .commandUp])
    #expect(fixture.events.contains(.down(53)) == false)
  }

  @Test func backCancelsPendingTabBeforeEscapeAndCommandRelease() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.back, owner: owner))
    #expect(fixture.events.suffix(4) == [.up(48), .down(53), .up(53), .commandUp])
    #expect(fixture.session.isActive == false)
    #expect(fixture.session.handleRelease(.tv, owner: owner) == false)
  }

  @Test func backAfterTabUpPostsTheCompleteCancellationSequenceWithoutAnExtraTabUp() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    fixture.scheduler.advance(by: 20)
    #expect(fixture.events == [.commandDown, .down(48), .up(48)])

    #expect(fixture.session.handlePress(.back, owner: owner))

    #expect(
      fixture.events == [
        .commandDown, .down(48), .up(48), .down(53), .up(53), .commandUp,
      ])
    #expect(fixture.session.isActive == false)
    #expect(fixture.session.handleRelease(.tv, owner: owner) == false)
    let count = fixture.events.count
    fixture.scheduler.advance(by: 40_000)
    #expect(fixture.events.count == count)
  }

  @Test(arguments: [true, false])
  func failedEscapePostingStillAttemptsCommandRelease(failingOnKeyDown: Bool) {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    fixture.scheduler.advance(by: 20)
    fixture.failedEvent = failingOnKeyDown ? .down(53) : .up(53)

    #expect(fixture.session.handlePress(.back, owner: owner))

    #expect(fixture.failedEvent == nil)
    #expect(
      fixture.events == [
        .commandDown, .down(48), .up(48), .down(53), .up(53), .commandUp,
      ])
    #expect(fixture.session.isActive == false)
    let count = fixture.events.count
    fixture.scheduler.advance(by: 40_000)
    #expect(fixture.events.count == count)
  }

  @Test(arguments: [RemoteButton.left, .right, .ok, .volumeUp])
  func unrelatedButtonsCancelBeforeTheirOrdinaryMappings(_ button: RemoteButton) {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(button, owner: owner) == false)
    #expect(fixture.events.suffix(4) == [.up(48), .down(53), .up(53), .commandUp])
    #expect(fixture.session.isActive == false)
    let count = fixture.events.count
    fixture.scheduler.advance(by: 1_000)
    #expect(fixture.events.count == count)
  }

  @Test func anotherRemoteCannotSubmitOrCancelByAnUnrelatedRelease() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    fixture.session.cancel(owner: UUID())
    #expect(fixture.session.isActive)
    #expect(fixture.session.handleRelease(.tv, owner: UUID()) == false)
    #expect(fixture.session.isActive)

    #expect(fixture.session.handlePress(.tv, owner: UUID()) == false)
    #expect(fixture.events.last == .commandUp)
    #expect(fixture.events.contains(.down(53)))
    #expect(fixture.session.isActive == false)
  }

  @Test func automaticRepeatsDoNotExtendTheMaximumHoldTimeout() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    fixture.scheduler.advance(by: 29_999)
    #expect(fixture.session.isActive)
    #expect(fixture.events.filter { $0 == .down(48) }.count > 2)
    #expect(fixture.session.handlePress(.tv, owner: owner))
    fixture.scheduler.advance(by: 1)
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.suffix(3) == [.down(53), .up(53), .commandUp])
    let count = fixture.events.count
    fixture.scheduler.advance(by: 1_000)
    #expect(fixture.events.count == count)
  }

  @Test func staleKeyUpRepeatAndTimeoutCallbacksCannotAffectAnotherSession() {
    let fixture = SwitcherFixture()
    #expect(fixture.session.begin(owner: UUID()))
    let oldTasks = fixture.scheduler.tasks
    fixture.session.cancel()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    let events = fixture.events

    for task in oldTasks { task.action() }

    #expect(fixture.events == events)
    #expect(fixture.session.isOwned(by: owner))
    #expect(fixture.session.handleRelease(.tv, owner: owner))
    let count = fixture.events.count
    fixture.scheduler.advance(by: 40_000)
    #expect(fixture.events.count == count)
  }

  @Test func missingAndRevokedPermissionsNeverLeaveCommandHeld() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    fixture.trusted = false
    #expect(fixture.session.begin(owner: owner) == false)
    #expect(fixture.events.isEmpty)

    fixture.trusted = true
    #expect(fixture.session.begin(owner: owner))
    fixture.trusted = false
    #expect(fixture.session.handlePress(.tv, owner: owner))
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.suffix(4) == [.up(48), .down(53), .up(53), .commandUp])

    fixture.trusted = true
    #expect(fixture.session.begin(owner: owner))
    fixture.scheduler.advance(by: 20)
    fixture.trusted = false
    fixture.scheduler.advance(by: 330)
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.last == .commandUp)
  }

  @Test(arguments: SwitcherFailureStage.allCases)
  func failedInjectionCancelsAllTimersAndAttemptsModifierCleanup(stage: SwitcherFailureStage) {
    let fixture = SwitcherFixture()
    let owner = UUID()
    switch stage {
    case .commandDown: fixture.failedEvent = .commandDown
    case .openingTabDown: fixture.failedEvent = .down(48)
    case .openingTabUp, .repeatTabDown, .repeatTabUp: break
    }

    let opened = fixture.session.begin(owner: owner)
    switch stage {
    case .commandDown, .openingTabDown:
      #expect(opened == false)
    case .openingTabUp:
      #expect(opened)
      fixture.failedEvent = .up(48)
      fixture.scheduler.advance(by: 20)
    case .repeatTabDown:
      #expect(opened)
      fixture.scheduler.advance(by: 20)
      fixture.failedEvent = .down(48)
      fixture.scheduler.advance(by: 330)
    case .repeatTabUp:
      #expect(opened)
      fixture.scheduler.advance(by: 350)
      fixture.failedEvent = .up(48)
      fixture.scheduler.advance(by: 20)
    }
    #expect(fixture.session.isActive == false)
    #expect(fixture.events.last == .commandUp)
    if stage != .commandDown {
      #expect(fixture.events.contains(.up(48)))
      #expect(fixture.events.contains(.down(53)))
    }
    let count = fixture.events.count
    fixture.scheduler.advance(by: 40_000)
    #expect(fixture.events.count == count)
  }

  @Test func reopeningCancelsTheOldHoldBeforePostingAnotherCommandDown() {
    let fixture = SwitcherFixture()
    #expect(fixture.session.begin(owner: UUID()))
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(
      fixture.events.suffix(6) == [
        .up(48), .down(53), .up(53), .commandUp, .commandDown, .down(48),
      ])
    #expect(fixture.session.isOwned(by: owner))
    fixture.session.cancel(owner: owner)
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
  case commandDown, openingTabDown, openingTabUp, repeatTabDown, repeatTabUp
}

private struct SwitcherKeyEvent: Equatable {
  let code: CGKeyCode
  let isDown: Bool
  let flags: CGEventFlags

  static let commandDown = Self(code: 55, isDown: true, flags: .maskCommand)
  static let commandUp = Self(code: 55, isDown: false, flags: [])
  static func down(_ code: CGKeyCode) -> Self {
    Self(code: code, isDown: true, flags: .maskCommand)
  }
  static func up(_ code: CGKeyCode) -> Self {
    Self(code: code, isDown: false, flags: .maskCommand)
  }
}

@MainActor
private final class SwitcherFixture {
  var trusted = true
  var failedEvent: SwitcherKeyEvent?
  var events: [SwitcherKeyEvent] = []
  let scheduler = SwitcherTestScheduler()
  lazy var session = AppSwitcherSession(
    scheduler: scheduler,
    accessibilityTrusted: { [unowned self] in trusted },
    postKeyState: { [unowned self] code, isDown, flags in
      let event = SwitcherKeyEvent(code: code, isDown: isDown, flags: flags)
      events.append(event)
      if event == failedEvent {
        failedEvent = nil
        return false
      }
      return true
    },
    diagnosticLogger: { _ in }
  )
}

private final class SwitcherTestTask: HIDRemoteScheduledTask {
  let id: Int
  let delay: UInt64
  var dueAt: UInt64
  let interval: UInt64?
  let action: () -> Void
  var cancelled = false

  init(id: Int, delay: UInt64, dueAt: UInt64, interval: UInt64?, action: @escaping () -> Void) {
    self.id = id
    self.delay = delay
    self.dueAt = dueAt
    self.interval = interval
    self.action = action
  }

  func cancel() { cancelled = true }
}

private final class SwitcherTestScheduler: HIDRemoteScheduling {
  private var now: UInt64 = 0
  private var nextID = 0
  var tasks: [SwitcherTestTask] = []

  func schedule(
    afterMilliseconds: UInt64,
    repeatingEveryMilliseconds: UInt64?,
    _ action: @escaping () -> Void
  ) -> HIDRemoteScheduledTask {
    nextID += 1
    let task = SwitcherTestTask(
      id: nextID, delay: afterMilliseconds, dueAt: now + afterMilliseconds,
      interval: repeatingEveryMilliseconds, action: action)
    tasks.append(task)
    return task
  }

  func advance(by milliseconds: UInt64) {
    let target = now + milliseconds
    while let task = tasks.filter({ !$0.cancelled && $0.dueAt <= target })
      .min(by: { ($0.dueAt, $0.id) < ($1.dueAt, $1.id) })
    {
      now = task.dueAt
      if let interval = task.interval { task.dueAt += interval } else { task.cancelled = true }
      task.action()
    }
    tasks.removeAll { $0.cancelled }
    now = target
  }
}
