// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "RemoteMic",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "RemoteMic", targets: ["RemoteMic"])
  ],
  targets: [
    .executableTarget(
      name: "RemoteMic",
      dependencies: ["AudioExceptionGuard"],
      path: "Sources/RemoteMic",
      sources: [
        "ATVVProtocol.swift",
        "AccessibilityCaptureState.swift",
        "AppLogger.swift",
        "AppRuntimeState.swift",
        "AppSettings.swift",
        "AudioOutput.swift",
        "BluetoothLifecycle.swift",
        "BridgeAppModel.swift",
        "ButtonMappingSettingsView.swift",
        "ConnectionAudioSettingsView.swift",
        "CustomApplicationEditorRow.swift",
        "DoubaoAudioDevice.swift",
        "HIDRemoteMonitor.swift",
        "HIDRemoteScheduler.swift",
        "KeyboardEventSuppressor.swift",
        "KeyboardInjector.swift",
        "KeyboardShortcutPicker.swift",
        "KeyableSettingsPanel.swift",
        "Localization.swift",
        "LoginItemManager.swift",
        "MappingActionControl.swift",
        "NativeStatusMenuController.swift",
        "PermissionRow.swift",
        "PermissionSettingsView.swift",
        "QuickMappingPresentation.swift",
        "RemoteButtonGestureRecognizer.swift",
        "RemoteButtons.swift",
        "RemoteDeviceProfile.swift",
        "RemoteMicApp.swift",
        "RemoteMicAppDelegate.swift",
        "RemoteProfileRow.swift",
        "RemoteVoiceFunctionMapper.swift",
        "RuntimeStatusRow.swift",
        "SayAllDesign.swift",
        "SettingsDivider.swift",
        "SettingsNavigationModel.swift",
        "SettingsPage.swift",
        "SettingsPageHeader.swift",
        "SettingsRow.swift",
        "SettingsSection.swift",
        "SettingsSidebarButton.swift",
        "SettingsView.swift",
        "SettingsWindowHeader.swift",
        "ShortcutCaptureMonitor.swift",
        "TestTone.swift",
        "VoiceFnTapSessionController.swift",
        "VoiceInputDestinationCoordinator.swift",
        "XiaomiBluetoothBridge.swift",
      ]
    ),
    .target(
      name: "AudioExceptionGuard",
      path: "Sources/AudioExceptionGuard",
      publicHeadersPath: "include"
    ),
    .testTarget(
      name: "RemoteMicTests",
      dependencies: ["RemoteMic"],
      path: "Tests/RemoteMicTests"
    ),
  ],
  swiftLanguageModes: [.v5]
)
