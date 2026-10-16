import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct AppSwitcherSessionTests {
  @Test func navigationChangesTheSelectedApplicationAndOKActivatesOnlyThatTarget() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.applications == fixture.availableApplications)
    #expect(fixture.session.selectedIndex == 1)
    #expect(fixture.session.selectedApplication?.processIdentifier == 22)
    #expect(fixture.presenter.events == [.show([11, 22, 33], 1)])
    #expect(fixture.session.isOwned(by: owner))

    #expect(fixture.session.handlePress(.tv, owner: owner))
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.selectedApplication?.processIdentifier == 33)
    #expect(fixture.session.handlePress(.left, owner: owner))
    #expect(fixture.session.selectedApplication?.processIdentifier == 22)
    #expect(fixture.presenter.events.suffix(2) == [.select(2), .select(1)])
    #expect(fixture.activatedApplications.isEmpty)

    #expect(fixture.session.handlePress(.ok, owner: owner))
    #expect(fixture.session.isActive == false)
    #expect(fixture.activatedApplications == [fixture.availableApplications[1]])
    #expect(fixture.presenter.events.suffix(2) == [.dismiss, .activate(22)])
    let count = fixture.presenter.events.count
    fixture.session.cancel()
    #expect(fixture.presenter.events.count == count)
  }

  @Test func navigationWrapsInBothDirections() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.selectedIndex == 2)
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.selectedIndex == 0)
    #expect(fixture.session.selectedApplication?.processIdentifier == 11)
    #expect(fixture.session.handlePress(.left, owner: owner))
    #expect(fixture.session.selectedIndex == 2)
    #expect(fixture.session.selectedApplication?.processIdentifier == 33)
    #expect(fixture.presenter.events.suffix(3) == [.select(2), .select(0), .select(2)])
    #expect(fixture.activatedApplications.isEmpty)
    fixture.session.cancel()
  }

  @Test func noRunningApplicationsDoesNotPresentAnEmptyPanel() {
    let fixture = SwitcherFixture()
    fixture.availableApplications = []

    #expect(fixture.session.begin(owner: UUID()) == false)
    #expect(fixture.session.isActive == false)
    #expect(fixture.session.selectedApplication == nil)
    #expect(fixture.presenter.events.isEmpty)
    #expect(fixture.activatedApplications.isEmpty)
  }

  @Test func oneApplicationRemainsSelectedInBothDirections() {
    let fixture = SwitcherFixture()
    fixture.availableApplications = [fixture.availableApplications[0]]
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.selectedIndex == 0)
    #expect(fixture.session.handlePress(.left, owner: owner))
    #expect(fixture.session.selectedIndex == 0)
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.selectedApplication?.processIdentifier == 11)
    #expect(fixture.session.handlePress(.ok, owner: owner))
    #expect(fixture.activatedApplications == fixture.availableApplications)
  }

  @Test func backDismissesWithoutActivatingAnyApplication() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.right, owner: owner))
    #expect(fixture.session.handlePress(.back, owner: owner))
    #expect(fixture.presenter.events.last == .dismiss)
    #expect(fixture.activatedApplications.isEmpty)
    #expect(fixture.session.isActive == false)
  }

  @Test func unrelatedInputAndAnotherRemoteCancelBeforeNormalHandling() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    #expect(fixture.session.handlePress(.left, owner: owner) == false)
    #expect(fixture.presenter.events.isEmpty)
    #expect(fixture.session.begin(owner: owner))
    fixture.session.cancel(owner: UUID())
    #expect(fixture.session.isActive)

    #expect(fixture.session.handlePress(.ok, owner: UUID()) == false)
    #expect(fixture.presenter.events.last == .dismiss)
    #expect(fixture.session.isActive == false)
    #expect(fixture.activatedApplications.isEmpty)

    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.volumeUp, owner: owner) == false)
    #expect(fixture.presenter.events.last == .dismiss)
    #expect(fixture.session.isActive == false)
    #expect(fixture.activatedApplications.isEmpty)
  }

  @Test func onlyTheCurrentIdleTimerCanDismissTheSession() throws {
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
    #expect(fixture.presenter.events.last == .dismiss)
    #expect(fixture.activatedApplications.isEmpty)
    let count = fixture.presenter.events.count
    currentTimer.action()
    #expect(fixture.presenter.events.count == count)
  }

  @Test func missingOrRevokedPermissionDoesNotActivateAnApplication() {
    let fixture = SwitcherFixture()
    let owner = UUID()
    fixture.trusted = false
    #expect(fixture.session.begin(owner: owner) == false)
    #expect(fixture.presenter.events.isEmpty)
    fixture.trusted = true
    #expect(fixture.session.begin(owner: owner))
    fixture.trusted = false
    #expect(fixture.session.handlePress(.left, owner: owner))
    #expect(fixture.session.isActive == false)
    #expect(fixture.presenter.events.last == .dismiss)
    #expect(fixture.activatedApplications.isEmpty)
  }

  @Test func activationFailureStillClosesThePanelAndCannotBeSubmittedTwice() {
    let fixture = SwitcherFixture()
    fixture.activationSucceeds = false
    let owner = UUID()
    #expect(fixture.session.begin(owner: owner))
    #expect(fixture.session.handlePress(.ok, owner: owner))

    #expect(fixture.session.isActive == false)
    #expect(fixture.presenter.events.suffix(2) == [.dismiss, .activate(22)])
    #expect(fixture.activatedApplications == [fixture.availableApplications[1]])
    #expect(fixture.session.handlePress(.ok, owner: owner) == false)
    #expect(fixture.activatedApplications.count == 1)
  }

  @Test func reopeningDismissesThePreviousSelectionBeforePresentingAnother() {
    let fixture = SwitcherFixture()
    #expect(fixture.session.begin(owner: UUID()))
    let nextOwner = UUID()
    #expect(fixture.session.begin(owner: nextOwner))
    #expect(fixture.presenter.events.suffix(2) == [.dismiss, .show([11, 22, 33], 1)])
    #expect(fixture.session.isOwned(by: nextOwner))
    #expect(fixture.activatedApplications.isEmpty)
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
    #expect(fixture.presenter.events.isEmpty)
    fixture.session.updatePressedButtons([], owner: other)
    #expect(fixture.session.canBegin(owner: owner))
    #expect(fixture.session.begin(owner: owner))
    fixture.session.cancel()
    #expect(fixture.activatedApplications.isEmpty)
  }
}

private enum SwitcherPresentationEvent: Equatable {
  case show([Int32], Int)
  case select(Int)
  case dismiss
  case activate(Int32)
}

@MainActor
private final class SwitcherTestPresenter: AppSwitcherPresenting {
  var events: [SwitcherPresentationEvent] = []

  func show(applications: [AppSwitcherApplication], selectedIndex: Int) {
    events.append(.show(applications.map(\.processIdentifier), selectedIndex))
  }

  func select(index: Int) { events.append(.select(index)) }

  func dismiss() { events.append(.dismiss) }
}

@MainActor
private final class SwitcherFixture {
  var trusted = true
  var activationSucceeds = true
  var availableApplications = [Int32(11), 22, 33].map { identifier in
    AppSwitcherApplication(
      processIdentifier: identifier,
      bundleIdentifier: "com.example.switcher.\(identifier)",
      name: "App \(identifier)",
      bundleURL: URL(fileURLWithPath: "/Applications/TestApp\(identifier).app")
    )
  }
  var activatedApplications: [AppSwitcherApplication] = []
  let presenter = SwitcherTestPresenter()
  let scheduler = SwitcherTestScheduler()
  lazy var session = AppSwitcherSession(
    scheduler: scheduler,
    accessibilityTrusted: { [unowned self] in trusted },
    applications: { [unowned self] in availableApplications },
    activateApplication: { [unowned self] application in
      presenter.events.append(.activate(application.processIdentifier))
      activatedApplications.append(application)
      return activationSucceeds
    },
    presenter: presenter,
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
