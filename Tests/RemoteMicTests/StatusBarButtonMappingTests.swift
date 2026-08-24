import Foundation
import Testing

@testable import RemoteMic

@MainActor
struct StatusBarButtonMappingTests {
  @Test(
    "Status item click behavior",
    arguments: [
      (isRightClick: true, expected: true),
      (isRightClick: false, expected: true),
    ]
  )
  func statusItemClickBehavior(
    scenario: (
      isRightClick: Bool,
      expected: Bool
    )
  ) {
    #expect(
      StatusItemClickPolicy.opensPanel(isRightClick: scenario.isRightClick) == scenario.expected
    )
  }

  @Test func quickActionSelectionUpdatesAndPersistsTheSingleClickMapping() throws {
    let suiteName = "RemoteMicTests.StatusBarMapping.Apply.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    let selection = QuickMappingActionSelection(button: .ok, action: .commandReturn)

    selection.apply(to: settings)

    #expect(settings.configuredAction(for: .ok, trigger: .singleClick).action == .commandReturn)
    #expect(
      AppSettings(defaults: defaults)
        .configuredAction(for: .ok, trigger: .singleClick).action == .commandReturn
    )
  }

  @Test func unconfiguredCustomActionsAreNotOfferedInTheQuickMenu() {
    let groups = ButtonMappingPresentation.actionGroups(
      installedBundleIdentifiers: [],
      currentAction: .returnKey,
      hasConfiguredShortcut: false,
      hasConfiguredApplication: false
    )
    let actions = groups.flatMap(\.actions)

    #expect(actions.contains(.customShortcut) == false)
    #expect(actions.contains(.openCustomApplication) == false)
    #expect(groups.map(\.category) == [.basicKeys, .systemAndMedia])
  }

  @Test func configuredCustomActionsRemainAvailableForFastSwitching() {
    let groups = ButtonMappingPresentation.actionGroups(
      installedBundleIdentifiers: [PresetApplication.codex.bundleIdentifier],
      currentAction: .returnKey,
      hasConfiguredShortcut: true,
      hasConfiguredApplication: true
    )
    let actions = groups.flatMap(\.actions)

    #expect(actions.contains(.customShortcut))
    #expect(actions.contains(.openCustomApplication))
    #expect(actions.contains(.openCodex))
    #expect(actions.contains(.openSafari) == false)
    #expect(groups.map(\.category) == ButtonActionCategory.allCases)
  }

  @Test func presentationReflectsSelectedRemoteAndCurrentButtonAction() throws {
    let suiteName = "RemoteMicTests.StatusBarMapping.Presentation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.customMappingEnabled = true
    let profileID = settings.registerHIDRemote(fingerprint: "status-menu-remote")
    settings.selectRemoteProfile(profileID)
    let localization = LocalizationStore(settings: settings)
    let profile = try #require(settings.selectedRemoteProfile)
    let configured = settings.configuredAction(for: .ok, trigger: .singleClick)

    let remoteName = ButtonMappingPresentation.remoteDisplayName(
      profile,
      among: settings.remoteDeviceProfiles,
      using: localization
    )
    let summary = ButtonMappingPresentation.actionSummary(
      configured: configured,
      customApplicationName: nil,
      using: localization
    )

    #expect(remoteName.isEmpty == false)
    #expect(configured.action == .returnKey)
    #expect(summary == configured.action.displayName(using: localization))
  }
}
