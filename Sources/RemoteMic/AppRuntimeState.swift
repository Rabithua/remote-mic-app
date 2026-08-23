import Foundation
import Observation

enum StatusMenuEntry: String, CaseIterable {
  case connectionStatus
  case audioStatus
  case hidStatus
  case reconnect
  case quickMapping
  case settings
  case launchAtLogin
  case language
  case logs
  case version
  case quit
}

enum RuntimeWarning: Hashable {
  case bluetoothPermission
  case inputMonitoringPermission
  case accessibilityPermission
  case noRemote
  case audioDeviceUnavailable
}

enum RuntimeWarningPolicy {
  static func warnings(
    bluetoothGranted: Bool,
    inputMonitoringGranted: Bool,
    accessibilityGranted: Bool,
    hasConnectedRemote: Bool,
    audioDeviceAvailable: Bool
  ) -> Set<RuntimeWarning> {
    var warnings = Set<RuntimeWarning>()
    if !bluetoothGranted { warnings.insert(.bluetoothPermission) }
    if !inputMonitoringGranted { warnings.insert(.inputMonitoringPermission) }
    if !accessibilityGranted { warnings.insert(.accessibilityPermission) }
    if !hasConnectedRemote { warnings.insert(.noRemote) }
    if !audioDeviceAvailable { warnings.insert(.audioDeviceUnavailable) }
    return warnings
  }
}

struct HIDPermissionSnapshot: Equatable {
  let inputMonitoringGranted: Bool
  let accessibilityGranted: Bool

  @MainActor
  static var current: HIDPermissionSnapshot {
    HIDPermissionSnapshot(
      inputMonitoringGranted: HIDRemoteMonitor.isInputMonitoringGranted,
      accessibilityGranted: KeyboardInjector.isAccessibilityTrusted
    )
  }
}

enum HIDPermissionRecoveryPolicy {
  static func shouldReapplySettings(
    started: Bool,
    customMappingEnabled: Bool,
    previous: HIDPermissionSnapshot?,
    current: HIDPermissionSnapshot
  ) -> Bool {
    guard started, customMappingEnabled, let previous else { return false }
    return previous != current
  }
}

@MainActor
@Observable
final class AppRuntimeState {
  var connectionStatus = LocalizedMessage("bluetooth.status.initializing")
  var hidStatus = LocalizedMessage("button_mapping.status.disabled")
  var audioStatus = LocalizedMessage("audio.output.none_selected")
  var doubaoAudioStatus = LocalizedMessage("audio.compatibility.checking")
  var testToneStatus = LocalizedMessage("audio.output.none_selected")
  var voiceShortcutStatus = LocalizedMessage("voice_button.status.preparing")
  var isStreaming = false
  var isConnected = false
  var isVoiceTriggerEnabled = false
  var activeRemoteButtons = Set<RemoteButton>()
  var lastRemoteButtonPress: RemoteButton?
  var connectedRemoteProfileIDs = Set<UUID>()
  var remoteBatteryLevels: [UUID: Int] = [:]
  var remotePowerStates: [UUID: RemotePowerState] = [:]
  var audioDevices: [AudioDeviceInfo] = []
  var isPlayingTestTone = false
  var isAudioOutputReady = false
  var currentVoiceSampleCount: UInt64 = 0
}
