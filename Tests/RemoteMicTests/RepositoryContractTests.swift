import Foundation
import Testing

@testable import RemoteMic

@Suite("Headless repository contract")
struct RepositoryContractTests {
  @Test func statusMenuContainsTheRequiredHeadlessControls() {
    #expect(
      StatusMenuEntry.allCases == [
        .connectionStatus,
        .audioStatus,
        .hidStatus,
        .reconnect,
        .quickMapping,
        .settings,
        .launchAtLogin,
        .language,
        .logs,
        .version,
        .quit,
      ])
    #expect(StatusItemClickPolicy.opensMenu(isRightClick: false))
    #expect(StatusItemClickPolicy.opensMenu(isRightClick: true))
  }

  @Test func missingRuntimeRequirementsProduceMenuWarnings() {
    let warnings = RuntimeWarningPolicy.warnings(
      bluetoothGranted: false,
      inputMonitoringGranted: false,
      accessibilityGranted: false,
      hasConnectedRemote: false,
      audioDeviceAvailable: false
    )
    #expect(
      warnings == [
        .bluetoothPermission,
        .inputMonitoringPermission,
        .accessibilityPermission,
        .noRemote,
        .audioDeviceUnavailable,
      ])
  }

  @Test func appIdentityAndHeadlessMetadataStayStable() throws {
    let plist = try propertyList("Resources/Info.plist")
    #expect(plist["CFBundleIdentifier"] as? String == "com.hd838a.RemoteMic")
    #expect(plist["CFBundleExecutable"] as? String == "RemoteMic")
    #expect(plist["CFBundleDisplayName"] as? String == "SayAll")
    #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
    #expect(plist["LSUIElement"] as? Bool == true)
    #expect(plist.keys.allSatisfy { !$0.hasPrefix("SU") })
    #expect(plist["NSLocalNetworkUsageDescription"] == nil)
    #expect(plist["NSBonjourServices"] == nil)
    #expect(plist["CFBundleIconFile"] == nil)
  }

  @Test func packageHasNoRemoteDependenciesOrRemovedExecutables() throws {
    let manifest = try contents("Package.swift")
    #expect(!manifest.contains(".package("))
    #expect(!manifest.contains("Sparkle"))
    #expect(!manifest.contains("SayAllMCP"))
    #expect(!manifest.contains("sayall-mac-remote"))
    #expect(manifest.contains(".macOS(.v14)"))
  }

  @Test func compactSettingsKeepSpecifiedWindowAndFullSurfaceHitTargets() throws {
    let app = try contents("Sources/RemoteMic/RemoteMicApp.swift")
    let settings = try contents("Sources/RemoteMic/SettingsView.swift")

    #expect(app.contains("NSApp.setActivationPolicy(.accessory)"))
    #expect(app.contains("[.leftMouseUp, .rightMouseUp]"))
    #expect(app.contains("width: 820, height: 620"))
    #expect(app.contains("width: 760, height: 540"))
    #expect(settings.components(separatedBy: ".contentShape(Rectangle())").count >= 8)
  }

  @Test func englishAndChineseLocalizationKeysMatch() throws {
    let english = try strings("Resources/en.lproj/Localizable.strings")
    let chinese = try strings("Resources/zh-Hans.lproj/Localizable.strings")
    #expect(Set(english.keys) == Set(chinese.keys))
    for required in [
      "settings.section.connection_audio",
      "menu.launch_at_login",
      "setup.action.done",
      "permissions.restart_hint",
    ] {
      #expect(english[required]?.isEmpty == false)
      #expect(chinese[required]?.isEmpty == false)
    }
  }

  @Test func repositoryKeepsOnlyTheSupportedScriptsAndWorkflow() throws {
    let scripts = try FileManager.default.contentsOfDirectory(
      at: repositoryRoot.appendingPathComponent("scripts"),
      includingPropertiesForKeys: nil
    )
    .map(\.lastPathComponent)
    .sorted()

    #expect(
      scripts == [
        "build-app.sh",
        "build-driver.sh",
        "install-local.sh",
        "run-local.sh",
        "test.sh",
        "verify-app.sh",
        "verify-driver.sh",
      ])

    let workflows = try FileManager.default.contentsOfDirectory(
      at: repositoryRoot.appendingPathComponent(".github/workflows"),
      includingPropertiesForKeys: nil
    )
    .map(\.lastPathComponent)
    #expect(workflows == ["mac-ci.yml"])
  }

  @Test func localInstallerKeepsItsSafetyBoundaries() throws {
    let installer = try contents("scripts/install-local.sh")
    let driverBuilder = try contents("scripts/build-driver.sh")

    for required in [
      "/Applications/SayAll.app",
      "/Library/Audio/Plug-Ins/HAL/MiRemoteV2ch.driver",
      "com.hd838a.RemoteMic",
      "com.hd838a.MiRemoteV2ch",
      "refusing to replace a symbolic-link destination",
      "Bundle ID does not match",
      ".backup-$timestamp",
      "Previous.app",
      "app replacement failed; previous installation was restored",
    ] {
      #expect(installer.contains(required))
    }
    #expect(
      driverBuilder.contains("e2b22aaaba4e507a097131704bf96dabc004d9cf")
    )
    #expect(driverBuilder.contains("/private/tmp/remote-mic-driver-"))
    #expect(!installer.contains("LaunchAgent"))
  }

  private func contents(_ relativePath: String) throws -> String {
    try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  private func propertyList(_ relativePath: String) throws -> [String: Any] {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    return try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
  }

  private func strings(_ relativePath: String) throws -> [String: String] {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    return try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
    )
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
