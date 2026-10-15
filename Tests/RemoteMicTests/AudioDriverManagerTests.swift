import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct AudioDriverManagerTests {
  @Test(arguments: [AudioDriverStatus.ready, .conflict, .unavailable])
  func healthyAndConflictingDriversNeverRequestElevation(_ status: AudioDriverStatus) async {
    let service = FakeAudioDriverService(status: status)
    let manager = AudioDriverManager(service: service)
    await manager.refresh()
    let installed = await manager.install()
    #expect(installed == false)
    #expect(await service.installCount == 0)
    #expect(manager.status == status)
  }

  @Test(arguments: [AudioDriverStatus.missing, .needsRepair])
  func installationVerifiesTheResult(_ status: AudioDriverStatus) async {
    let service = FakeAudioDriverService(status: status)
    let manager = AudioDriverManager(service: service)
    await manager.refresh()
    #expect(await manager.install())
    #expect(manager.status == .ready)
    #expect(manager.isInstalling == false)
    #expect(await service.installCount == 1)
  }

  @Test(arguments: [FakeAudioDriverService.Outcome.cancel, .fail, .invalidInstallation])
  func cancellationAndErrorsAllowRetry(_ outcome: FakeAudioDriverService.Outcome) async {
    let service = FakeAudioDriverService(status: .missing, outcome: outcome)
    let manager = AudioDriverManager(service: service)
    await manager.refresh()
    #expect(await manager.install() == false)
    #expect(manager.status == .missing)
    #expect(manager.isInstalling == false)
    #expect(
      manager.message?.key
        == (outcome == .cancel ? "device_setup.driver.cancelled" : "device_setup.driver.failed"))
    await service.setOutcome(.succeed)
    #expect(await manager.install())
  }

  @Test func duplicateInstallIsIgnoredWhileAuthorizationIsPending() async {
    let service = FakeAudioDriverService(status: .missing, outcome: .wait)
    let manager = AudioDriverManager(service: service)
    await manager.refresh()
    let first = Task { await manager.install() }
    await service.waitForInstall()
    #expect(manager.isInstalling)
    #expect(await manager.install() == false)
    await service.finishInstall()
    #expect(await first.value)
    #expect(await service.installCount == 1)
  }

  @Test func aBareExecutableReportsMissingBundledResources() async {
    let service = BundledAudioDriverService(resourceURL: nil)
    #expect(await service.status() == .unavailable)
  }

  @Test func firstSetupSelectsTheBundledDeviceWithoutOverwritingExistingPreferences() throws {
    let suiteName = "RemoteMicTests.AudioSetup.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let device = AudioDeviceInfo(
      id: 1, uid: DoubaoAudioDevicePolicy.deviceUID, name: "MiRemoteV 2ch")
    let settings = AppSettings(defaults: defaults)
    #expect(settings.selectInitialAudioDeviceIfNeeded(from: []) == false)
    #expect(settings.hasConfiguredAudioDevice == false)
    #expect(settings.selectInitialAudioDeviceIfNeeded(from: [device]))
    #expect(AppSettings(defaults: defaults).selectedAudioDeviceUID == device.uid)
    settings.selectedAudioDeviceUID = ""
    #expect(settings.selectInitialAudioDeviceIfNeeded(from: [device]) == false)
    #expect(AppSettings(defaults: defaults).selectedAudioDeviceUID == "")
    settings.selectedAudioDeviceUID = "existing-audio-device"
    #expect(settings.selectInitialAudioDeviceIfNeeded(from: [device]) == false)
    #expect(settings.selectedAudioDeviceUID == "existing-audio-device")
  }
}

actor FakeAudioDriverService: AudioDriverServicing {
  enum Outcome: Sendable { case succeed, cancel, fail, invalidInstallation, wait }
  private var currentStatus: AudioDriverStatus
  private var outcome: Outcome
  private(set) var installCount = 0
  private var installWaiter: CheckedContinuation<Void, Never>?
  private var finishWaiter: CheckedContinuation<Void, Never>?

  init(status: AudioDriverStatus, outcome: Outcome = .succeed) {
    currentStatus = status
    self.outcome = outcome
  }

  func status() async -> AudioDriverStatus { currentStatus }
  func setOutcome(_ outcome: Outcome) { self.outcome = outcome }

  func install() async throws {
    installCount += 1
    switch outcome {
    case .succeed: currentStatus = .ready
    case .cancel: throw CancellationError()
    case .fail: throw CocoaError(.fileWriteNoPermission)
    case .invalidInstallation: break
    case .wait:
      await withCheckedContinuation { continuation in
        finishWaiter = continuation
        installWaiter?.resume()
        installWaiter = nil
      }
      currentStatus = .ready
    }
  }

  func waitForInstall() async {
    if installCount > 0 { return }
    await withCheckedContinuation { installWaiter = $0 }
  }

  func finishInstall() {
    finishWaiter?.resume()
    finishWaiter = nil
  }
}
