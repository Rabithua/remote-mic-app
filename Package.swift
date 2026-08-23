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
        "AppLogger.swift",
        "AppRuntimeState.swift",
        "AppSettings.swift",
        "AudioOutput.swift",
        "BluetoothLifecycle.swift",
        "BridgeAppModel.swift",
        "DoubaoAudioDevice.swift",
        "HIDRemoteMonitor.swift",
        "HIDRemoteScheduler.swift",
        "KeyboardEventSuppressor.swift",
        "KeyboardInjector.swift",
        "KeyboardShortcutPicker.swift",
        "Localization.swift",
        "LoginItemManager.swift",
        "RemoteButtonGestureRecognizer.swift",
        "RemoteButtons.swift",
        "RemoteDeviceProfile.swift",
        "RemoteMicApp.swift",
        "RemoteVoiceFunctionMapper.swift",
        "SettingsView.swift",
        "ShortcutCaptureMonitor.swift",
        "StatusBarButtonMappingMenu.swift",
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
