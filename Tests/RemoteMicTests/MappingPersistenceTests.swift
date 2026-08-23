import AppKit
import Foundation
import Testing

@testable import RemoteMic

@Suite("Mapping persistence", .serialized)
@MainActor
struct MappingPersistenceTests {
  @Test func singleDoubleAndLongPressChangesPersistImmediately() throws {
    let store = try TemporaryDefaults()
    defer { store.remove() }
    let settings = AppSettings(defaults: store.defaults)

    settings.setAction(.commandReturn, for: .ok, trigger: .singleClick)
    settings.setAction(.commandCopy, for: .ok, trigger: .doubleClick)
    settings.setAction(.commandPaste, for: .ok, trigger: .longPress)

    let restored = AppSettings(defaults: store.defaults)
    #expect(restored.configuredAction(for: .ok, trigger: .singleClick).action == .commandReturn)
    #expect(restored.configuredAction(for: .ok, trigger: .doubleClick).action == .commandCopy)
    #expect(restored.configuredAction(for: .ok, trigger: .longPress).action == .commandPaste)
  }

  @Test func shortcutAndCustomApplicationConfigurationArePreserved() throws {
    let store = try TemporaryDefaults()
    defer { store.remove() }
    let settings = AppSettings(defaults: store.defaults)
    let shortcut = CustomKeyboardShortcut(
      keyCode: 8,
      modifierFlags: [.command, .shift],
      keyLabel: "C"
    )
    let application = CustomApplicationProfile(
      displayName: "Example",
      bundleIdentifier: "com.example.editor",
      applicationPath: "/Applications/Example.app",
      focusStrategy: .keyboardShortcut,
      focusShortcut: shortcut
    )
    settings.addCustomApplicationProfile(application)
    settings.setAction(.customShortcut, for: .menu, trigger: .doubleClick)
    settings.setShortcut(shortcut, for: .menu, trigger: .doubleClick)
    settings.setAction(.openCustomApplication, for: .tv, trigger: .longPress)
    settings.setApplicationProfileID(application.id, for: .tv, trigger: .longPress)

    let restored = AppSettings(defaults: store.defaults)
    #expect(restored.configuredAction(for: .menu, trigger: .doubleClick).shortcut == shortcut)
    #expect(restored.customApplicationProfile(id: application.id) == application)
    #expect(
      restored.configuredAction(for: .tv, trigger: .longPress).applicationProfileID
        == application.id
    )
  }

  @Test func multipleRemoteProfilesKeepMappingsIsolated() throws {
    let store = try TemporaryDefaults()
    defer { store.remove() }
    let settings = AppSettings(defaults: store.defaults)
    let first = settings.registerBluetoothRemote(identifier: UUID())
    settings.selectRemoteProfile(first)
    settings.setAction(.commandCopy, for: .ok, trigger: .singleClick)

    let second = settings.registerBluetoothRemote(identifier: UUID())
    settings.selectRemoteProfile(second)
    settings.setAction(.commandPaste, for: .ok, trigger: .singleClick)

    #expect(settings.action(for: .ok, profileID: first) == .commandCopy)
    #expect(settings.action(for: .ok, profileID: second) == .commandPaste)

    let restored = AppSettings(defaults: store.defaults)
    #expect(restored.action(for: .ok, profileID: first) == .commandCopy)
    #expect(restored.action(for: .ok, profileID: second) == .commandPaste)
  }

  @Test func freshAndLegacySetupStateMigrateOnce() throws {
    let fresh = try TemporaryDefaults()
    defer { fresh.remove() }
    let firstLaunch = AppSettings(defaults: fresh.defaults)
    #expect(!firstLaunch.setupHasPresented)
    #expect(!firstLaunch.setupCompleted)
    firstLaunch.markSetupPresented()
    #expect(AppSettings(defaults: fresh.defaults).setupHasPresented)
    #expect(!AppSettings(defaults: fresh.defaults).setupCompleted)
    firstLaunch.completeSetup()
    #expect(AppSettings(defaults: fresh.defaults).setupCompleted)

    let legacy = try TemporaryDefaults()
    defer { legacy.remove() }
    legacy.defaults.set(1, forKey: "onboarding.completedVersion")
    let migrated = AppSettings(defaults: legacy.defaults)
    #expect(migrated.setupHasPresented)
    #expect(migrated.setupCompleted)
    #expect(legacy.defaults.integer(forKey: "onboarding.completedVersion") == 1)
  }

  @Test func removedLongRecordingActionIsSafelyNormalized() throws {
    let store = try TemporaryDefaults()
    defer { store.remove() }
    let encoded = try JSONSerialization.data(
      withJSONObject: ["power": "toggleLongRecording"]
    )
    store.defaults.set(encoded, forKey: "buttonBindings")
    store.defaults.set(true, forKey: "experimentalContinuousRecordingEnabled")

    let settings = AppSettings(defaults: store.defaults)

    #expect(settings.action(for: .power) == .disabled)
    #expect(store.defaults.bool(forKey: "experimentalContinuousRecordingEnabled"))
  }
}

private struct TemporaryDefaults {
  let name: String
  let defaults: UserDefaults

  init() throws {
    name = "RemoteMicTests.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: name))
  }

  func remove() {
    defaults.removePersistentDomain(forName: name)
  }
}
