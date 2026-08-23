import AppKit
import CoreAudio
import CoreBluetooth
import Foundation

private struct ManagedDefaultInputTransition {
  let virtualUID: String
  let fallbackUID: String
}

enum BluetoothVoiceStopPolicy {
  static func shouldFlushAudio(handledByFnTapMode _: Bool) -> Bool { false }
}

@MainActor
final class BridgeAppModel: XiaomiBluetoothBridgeDelegate {
  let settings: AppSettings
  let state: AppRuntimeState

  private let audioOutput = VirtualAudioOutput()
  private let voiceFunctionMapper = RemoteVoiceFunctionMapper()
  private lazy var voiceInputDestinationCoordinator = VoiceInputDestinationCoordinator(
    onStateChange: { [weak self] state in
      self?.handleVoiceInputDestinationState(state)
    }
  )
  private lazy var voiceFnTapSession = VoiceFnTapSessionController(
    destinationReadiness: { [weak self] completion in
      self?.voiceInputDestinationCoordinator.waitUntilReady(completion: completion) ?? .immediate
    },
    setFunctionKeyPressed: { KeyboardInjector.setFunctionKeyPressed($0) },
    enqueueAudio: { [weak self] samples in
      _ = self?.audioOutput.enqueue(samples: samples)
    },
    drainAudio: { [weak self] completion in
      guard let self else {
        completion()
        return
      }
      self.audioOutput.endSessionAfterDraining(completion: completion)
    },
    onFailure: { [weak self] failure in
      self?.handleVoiceFnTapFailure(failure)
    }
  )

  private var bluetoothBridges: [UUID: XiaomiBluetoothBridge] = [:]
  private var bluetoothBridgeStates: [ObjectIdentifier: BluetoothBridgeState] = [:]
  private var discoveryBluetoothBridge: XiaomiBluetoothBridge?
  private var activeBluetoothVoiceDeviceIdentifier: UUID?
  private var bluetoothVoiceActive = false
  private var bluetoothVoiceTraceCounter: UInt64 = 0
  private var activeBluetoothVoiceTraceID: UInt64?
  private var bluetoothVoiceTraceStartedAt: Date?
  private var bluetoothVoiceTraceModel: XiaomiRemoteModel = .unknown
  private var bluetoothVoiceDecodedBatchCount = 0
  private var bluetoothVoiceDecodedSampleCount = 0
  private var bluetoothVoiceEnqueueFailureCount = 0
  private var bluetoothVoiceTraceRoute = "none"

  private let hidEventSuppressor = KeyboardEventSuppressor()
  private var hidMonitors: [String: HIDRemoteMonitor] = [:]
  private var discoveryHIDMonitor: HIDRemoteMonitor?
  private var hidPowerKeySuppressed = false
  private var hidAllowedLocationIDs: Set<UInt32>?
  private var appliedHIDPermissionSnapshot: HIDPermissionSnapshot?

  private var started = false
  private var terminationObserver: NSObjectProtocol?
  private var systemAudioSuspensionState = SystemAudioSuspensionState()
  private var managedDefaultInputTransition: ManagedDefaultInputTransition?
  private var testToneGeneration = 0

  init(
    settings: AppSettings,
    state: AppRuntimeState,
    initialAudioDevices: [AudioDeviceInfo] = []
  ) {
    self.settings = settings
    self.state = state
    state.audioDevices = initialAudioDevices
    audioOutput.onConfigurationChange = { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.started else { return }
        self.refreshAudioDevices()
        self.applyAudioSettings(reason: "engine_configuration_change")
      }
    }
  }

  func startIfNeeded() {
    guard !started else { return }
    started = true
    refreshAudioDevices()
    applyAudioSettings(reason: "startup")
    startBluetoothConnections()
    applyHIDSettings()
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.stop() }
    }
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "development"
    AppLogger.shared.write("APP START version=\(version)")
  }

  func stop() {
    guard started else { return }
    started = false
    cancelTestToneIfNeeded(
      statusMessage: LocalizedMessage("app.status.stopped"),
      logReason: "app_stop"
    )
    voiceInputDestinationCoordinator.shutdown()
    voiceFnTapSession.shutdown()
    for bridge in bluetoothBridges.values {
      bridge.stop()
    }
    discoveryBluetoothBridge?.stop()
    bluetoothBridges.removeAll()
    bluetoothBridgeStates.removeAll()
    discoveryBluetoothBridge = nil
    activeBluetoothVoiceDeviceIdentifier = nil
    bluetoothVoiceActive = false
    stopHIDMonitors()
    audioOutput.stop()
    voiceFunctionMapper.restore()
    state.isStreaming = false
    state.isConnected = false
    state.isAudioOutputReady = false
    state.connectionStatus = LocalizedMessage("common.status.stopped")
    state.audioStatus = LocalizedMessage("app.status.stopped")
    if let terminationObserver {
      NotificationCenter.default.removeObserver(terminationObserver)
      self.terminationObserver = nil
    }
    AppLogger.shared.write("APP STOP")
  }

  func reconnect() {
    guard started else { return }
    if bluetoothBridges.isEmpty, discoveryBluetoothBridge == nil {
      startBluetoothConnections()
      return
    }
    if let selectedBluetoothBridge {
      selectedBluetoothBridge.reconnectNow()
    } else {
      for bridge in bluetoothBridges.values {
        bridge.reconnectNow()
      }
      discoveryBluetoothBridge?.reconnectNow()
    }
    AppLogger.shared.write("BLE RECONNECT requested")
  }

  func refreshRemoteDiscovery() {
    guard started else { return }
    if discoveryBluetoothBridge == nil {
      startBluetoothDiscoveryIfNeeded()
    } else {
      discoveryBluetoothBridge?.reconnectNow()
    }
  }

  func refreshAudioDevices() {
    let devices = CoreAudioDeviceCatalog.outputDevices()
    state.audioDevices = devices
    state.doubaoAudioStatus = DoubaoAudioDevicePolicy.status(in: devices)
    AppLogger.shared.write(
      "AUDIO DEVICES refreshed outputs={\(CoreAudioDeviceCatalog.outputDevicesDiagnostic(devices))}"
    )
  }

  var hasDoubaoAudioDevice: Bool {
    DoubaoAudioDevicePolicy.device(in: state.audioDevices) != nil
  }

  func selectDoubaoAudioDevice() {
    guard let device = DoubaoAudioDevicePolicy.device(in: state.audioDevices) else {
      state.doubaoAudioStatus = LocalizedMessage(
        "audio.compatibility.device_missing",
        arguments: [DoubaoAudioDevicePolicy.deviceName]
      )
      return
    }
    settings.selectedAudioDeviceUID = device.uid
    applyAudioSettings(reason: "doubao_device_selected")
    state.doubaoAudioStatus = LocalizedMessage(
      "audio.compatibility.device_selected",
      arguments: [device.name]
    )
  }

  func applyAudioSettings(reason: String = "settings_change") {
    guard !settings.selectedAudioDeviceUID.isEmpty else {
      audioOutput.stop()
      state.audioStatus = LocalizedMessage("audio.output.none_selected")
      state.isAudioOutputReady = false
      state.testToneStatus = LocalizedMessage("audio.output.none_or_unavailable")
      return
    }
    _ = configureVirtualAudioOutput(reason: reason)
  }

  func handleSystemAudioLifecycle(_ event: SystemAudioLifecycleEvent) {
    let changed = systemAudioSuspensionState.apply(event)
    guard started, changed else { return }
    AppLogger.shared.write(
      "SYSTEM AUDIO event=\(event.rawValue) suspended=\(systemAudioSuspensionState.isSuspended) "
        + "reasons=\(systemAudioSuspensionState.diagnostic) voice=\(bluetoothVoiceActive)"
    )
    if event.isSuspending {
      guard !bluetoothVoiceActive, !state.isPlayingTestTone else { return }
      switchDefaultInputToFallbackIfNeeded(reason: event.rawValue)
      audioOutput.stop()
      state.isAudioOutputReady = false
      return
    }
    guard !systemAudioSuspensionState.isSuspended else { return }
    refreshAudioDevices()
    applyAudioSettings(reason: "system_\(event.rawValue)")
    for bridge in bluetoothBridges.values {
      bridge.reconnectNow()
    }
    discoveryBluetoothBridge?.reconnectNow()
  }

  var canSendTestTone: Bool {
    TestToneGate.canPlay(
      hasSelectedDevice: selectedAudioDeviceIsAvailable,
      isStreaming: state.isStreaming,
      isPlaying: state.isPlayingTestTone
    )
  }

  func sendTestTone() {
    guard canSendTestTone else {
      state.testToneStatus = LocalizedMessage(
        state.isStreaming
          ? "audio.test_tone.blocked_voice_active"
          : "audio.output.none_or_unavailable"
      )
      return
    }
    guard ensureVirtualAudioOutputReady(reason: "test_tone") else {
      state.testToneStatus = LocalizedMessage("audio.test_tone.device_not_ready")
      return
    }
    testToneGeneration &+= 1
    let generation = testToneGeneration
    let didStart = audioOutput.playTestTone { [weak self] finished in
      Task { @MainActor [weak self] in
        self?.handleTestToneCompletion(generation: generation, finished: finished)
      }
    }
    guard didStart else {
      state.testToneStatus = LocalizedMessage("audio.test_tone.device_not_ready")
      return
    }
    state.isPlayingTestTone = true
    state.testToneStatus = LocalizedMessage("audio.test_tone.playing")
  }

  func applyHIDSettings() {
    let snapshot = HIDPermissionSnapshot.current
    appliedHIDPermissionSnapshot = snapshot

    if !settings.customMappingEnabled {
      voiceFnTapSession.setEnabled(false)
      _ = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
      stopHIDMonitors()
      state.hidStatus = LocalizedMessage("button_mapping.status.system_managed")
      return
    }

    let wantsFnTap = settings.voiceFnTapModeEnabled
    var powerKeySuppressed: Bool
    if wantsFnTap, snapshot.accessibilityGranted {
      powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: true)
      if voiceFunctionMapper.isVoiceKeyNeutralized {
        voiceFnTapSession.setEnabled(true)
      } else {
        settings.voiceFnTapModeEnabled = false
        voiceFnTapSession.setEnabled(false)
        powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
      }
    } else {
      if wantsFnTap, !snapshot.accessibilityGranted {
        settings.voiceFnTapModeEnabled = false
      }
      voiceFnTapSession.setEnabled(false)
      powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
    }
    startHIDMonitors(powerKeySuppressed: powerKeySuppressed)
  }

  func refreshHIDAfterPermissionChange() {
    let current = HIDPermissionSnapshot.current
    guard
      HIDPermissionRecoveryPolicy.shouldReapplySettings(
        started: started,
        customMappingEnabled: settings.customMappingEnabled,
        previous: appliedHIDPermissionSnapshot,
        current: current
      )
    else { return }
    applyHIDSettings()
  }

  func setVoiceFnTapModeEnabled(_ enabled: Bool) {
    settings.voiceFnTapModeEnabled = enabled
    applyHIDSettings()
  }

  func requestInputMonitoringPermission() {
    _ = HIDRemoteMonitor.requestInputMonitoringAccess()
    openPrivacyPane("Privacy_ListenEvent")
  }

  func requestAccessibilityPermission() {
    _ = KeyboardInjector.requestAccessibilityAccess()
    openPrivacyPane("Privacy_Accessibility")
  }

  func requestBluetoothPermission() {
    reconnect()
    openPrivacyPane("Privacy_Bluetooth")
  }

  var bluetoothPermissionGranted: Bool {
    CBManager.authorization == .allowedAlways
  }

  func openLogFolder() {
    NSWorkspace.shared.activateFileViewerSelecting([AppLogger.shared.logURL])
  }

  func selectRemoteProfile(_ profileID: UUID) {
    settings.selectRemoteProfile(profileID)
    refreshBluetoothPresentation()
  }

  func batteryLevel(for profileID: UUID) -> Int? {
    state.remoteBatteryLevels[profileID]
  }

  func powerState(for profileID: UUID) -> RemotePowerState? {
    state.remotePowerStates[profileID]
  }

  func isRemoteConnected(_ profileID: UUID) -> Bool {
    state.connectedRemoteProfileIDs.contains(profileID)
  }

  private func configureVirtualAudioOutput(reason: String) -> Bool {
    cancelTestToneIfNeeded(
      statusMessage: LocalizedMessage("audio.test_tone.cancelled_device_changed"),
      logReason: "device_reconfigure"
    )
    let configured = audioOutput.configure(deviceUID: settings.selectedAudioDeviceUID)
    state.audioStatus = audioOutput.status
    state.isAudioOutputReady = audioOutput.isReadyForTestTone
    state.testToneStatus = LocalizedMessage(
      state.isAudioOutputReady
        ? "audio.test_tone.ready"
        : "audio.output.none_or_unavailable"
    )
    AppLogger.shared.write(
      "AUDIO REBIND reason=\(reason) success=\(configured) state={\(audioOutput.diagnosticState())}"
    )
    if configured {
      restoreManagedDefaultInputIfAppropriate(reason: reason)
    }
    return configured
  }

  private func ensureVirtualAudioOutputReady(reason: String) -> Bool {
    state.isAudioOutputReady = audioOutput.isReadyForTestTone
    return state.isAudioOutputReady || configureVirtualAudioOutput(reason: reason)
  }

  private var selectedAudioDeviceIsAvailable: Bool {
    let uid = settings.selectedAudioDeviceUID
    return !uid.isEmpty && state.audioDevices.contains(where: { $0.uid == uid })
  }

  private func handleTestToneCompletion(generation: Int, finished: Bool) {
    guard generation == testToneGeneration, state.isPlayingTestTone else { return }
    state.isPlayingTestTone = false
    state.testToneStatus = LocalizedMessage(
      finished ? "audio.test_tone.completed" : "audio.test_tone.cancelled"
    )
  }

  private func cancelTestToneIfNeeded(statusMessage: LocalizedMessage, logReason: String) {
    guard state.isPlayingTestTone else { return }
    testToneGeneration &+= 1
    state.isPlayingTestTone = false
    audioOutput.cancelTestTone()
    state.testToneStatus = statusMessage
    AppLogger.shared.write("AUDIO TEST_TONE cancelled reason=\(logReason)")
  }

  private func switchDefaultInputToFallbackIfNeeded(reason: String) {
    guard managedDefaultInputTransition == nil else { return }
    let selectedUID = settings.selectedAudioDeviceUID
    guard !selectedUID.isEmpty,
      CoreAudioDeviceCatalog.defaultInputDevice()?.uid == selectedUID,
      let fallback = CoreAudioDeviceCatalog.preferredFallbackInput(excludingUID: selectedUID)
    else { return }
    let result = CoreAudioDeviceCatalog.setDefaultInputDevice(fallback)
    guard result == noErr else {
      AppLogger.shared.write("AUDIO DEFAULT_INPUT fallback_failed reason=\(reason) error=\(result)")
      return
    }
    managedDefaultInputTransition = ManagedDefaultInputTransition(
      virtualUID: selectedUID,
      fallbackUID: fallback.uid
    )
  }

  private func restoreManagedDefaultInputIfAppropriate(reason: String) {
    guard let transition = managedDefaultInputTransition else { return }
    let currentDefault = CoreAudioDeviceCatalog.defaultInputDevice()
    guard
      DefaultInputFallbackPolicy.shouldRestoreVirtualInput(
        managedVirtualUID: transition.virtualUID,
        selectedVirtualUID: settings.selectedAudioDeviceUID,
        managedFallbackUID: transition.fallbackUID,
        currentDefaultUID: currentDefault?.uid
      )
    else {
      managedDefaultInputTransition = nil
      return
    }
    guard
      let virtualInput = CoreAudioDeviceCatalog.inputDevices().first(where: {
        $0.uid == transition.virtualUID
      })
    else { return }
    if CoreAudioDeviceCatalog.setDefaultInputDevice(virtualInput) == noErr {
      managedDefaultInputTransition = nil
      AppLogger.shared.write("AUDIO DEFAULT_INPUT restored reason=\(reason)")
    }
  }

  private func startHIDMonitors(powerKeySuppressed: Bool) {
    stopHIDMonitors()
    hidPowerKeySuppressed = powerKeySuppressed
    hidAllowedLocationIDs = voiceFunctionMapper.powerSuppressedLocationIDs
    guard settings.customMappingEnabled else { return }
    _ = hidEventSuppressor.start()
    for profile in settings.remoteDeviceProfiles {
      guard let fingerprint = profile.hidFingerprint else { continue }
      let monitor = makeHIDMonitor(profileID: profile.id, targetFingerprint: fingerprint)
      hidMonitors[fingerprint] = monitor
      monitor.start(
        powerKeySuppressed: powerKeySuppressed,
        allowedLocationIDs: hidAllowedLocationIDs
      )
    }
    startHIDDiscoveryIfNeeded()
  }

  private func stopHIDMonitors() {
    for monitor in hidMonitors.values {
      monitor.stop()
    }
    discoveryHIDMonitor?.stop()
    hidMonitors.removeAll()
    discoveryHIDMonitor = nil
    hidEventSuppressor.stop()
    state.activeRemoteButtons = []
  }

  private func startHIDDiscoveryIfNeeded() {
    guard settings.customMappingEnabled, discoveryHIDMonitor == nil else { return }
    let monitor = makeHIDMonitor(
      profileID: nil,
      targetFingerprint: nil,
      excludedFingerprints: { [weak self] in
        guard let self else { return [] }
        return Set(self.hidMonitors.keys)
      }
    )
    discoveryHIDMonitor = monitor
    monitor.start(
      powerKeySuppressed: hidPowerKeySuppressed,
      allowedLocationIDs: hidAllowedLocationIDs
    )
  }

  private func makeHIDMonitor(
    profileID: UUID?,
    targetFingerprint: String?,
    excludedFingerprints: @escaping () -> Set<String> = { [] }
  ) -> HIDRemoteMonitor {
    let monitor = HIDRemoteMonitor(
      settings: settings,
      profileID: profileID,
      targetFingerprint: targetFingerprint,
      excludedFingerprints: excludedFingerprints,
      eventSuppressor: hidEventSuppressor,
      ownsEventSuppressor: false,
      actionPerformer: { [weak self] _, _, configured in
        self?.performExternalConfiguredAction(configured) ?? false
      }
    )
    monitor.onStatus = { [weak self, weak monitor] value in
      guard let self, let monitor else { return }
      if monitor.profileID == self.settings.selectedRemoteProfileID || monitor.profileID == nil {
        self.state.hidStatus = value
      }
    }
    monitor.onActiveButtons = { [weak self] profileID, buttons in
      guard let self, profileID == self.settings.selectedRemoteProfileID else { return }
      self.state.activeRemoteButtons = buttons
    }
    monitor.onButtonPressed = { [weak self, weak monitor] profileID, fingerprint, button in
      guard let self, let monitor else { return profileID.map { ($0, true) } }
      self.state.lastRemoteButtonPress = button
      let existingID = profileID ?? self.settings.profileID(forHIDFingerprint: fingerprint)
      let resolvedID = existingID ?? self.settings.registerHIDRemote(fingerprint: fingerprint)
      if existingID == nil {
        monitor.assignProfileID(resolvedID)
        self.hidMonitors[fingerprint] = monitor
        if self.discoveryHIDMonitor === monitor {
          self.discoveryHIDMonitor = nil
          self.startHIDDiscoveryIfNeeded()
        }
      }
      self.selectRemoteProfile(resolvedID)
      return (resolvedID, true)
    }
    return monitor
  }

  private func performExternalConfiguredAction(_ configured: ConfiguredButtonAction) -> Bool {
    let applicationProfile = settings.customApplicationProfile(
      id: configured.applicationProfileID
    )
    let requestID =
      settings.voiceFnTapModeEnabled
      ? VoiceInputDestinationIntent.resolve(
        configured: configured,
        applicationProfile: applicationProfile
      ).map { voiceInputDestinationCoordinator.beginTargetSwitch(intent: $0) }
      : nil
    let handled = KeyboardInjector.send(
      configured.action,
      shortcut: configured.shortcut,
      applicationProfile: applicationProfile
    )
    if !handled, let requestID {
      voiceInputDestinationCoordinator.cancel(requestID: requestID, reason: .actionFailed)
    }
    return handled
  }

  private func handleVoiceInputDestinationState(_ destinationState: VoiceInputDestinationState) {
    guard settings.voiceFnTapModeEnabled else { return }
    switch destinationState {
    case .waiting:
      state.voiceShortcutStatus = LocalizedMessage("voice_button.status.waiting_for_input")
    case .ready:
      state.voiceShortcutStatus = LocalizedMessage("voice_button.status.input_ready")
    case .cancelled:
      state.voiceShortcutStatus = LocalizedMessage("voice_button.status.input_unavailable")
    }
  }

  private func handleVoiceFnTapFailure(_ failure: VoiceFnTapFailure) {
    AppLogger.shared.write("VOICE FN TAP failed reason=\(failure.rawValue) fallback=hardware_fn")
    settings.voiceFnTapModeEnabled = false
    voiceFnTapSession.setEnabled(false)
    applyHIDSettings()
  }

  @discardableResult
  private func applyVoiceFunctionMapping(neutralizeVoiceKey: Bool) -> Bool {
    let applied = voiceFunctionMapper.apply(
      suppressPowerKey: settings.customMappingEnabled,
      neutralizeVoiceKey: neutralizeVoiceKey
    )
    if !state.isStreaming {
      state.isVoiceTriggerEnabled = applied
      state.voiceShortcutStatus = LocalizedMessage(
        applied ? "voice_button.status.fn_enabled" : "voice_button.status.waiting"
      )
    }
    return !settings.customMappingEnabled || voiceFunctionMapper.isPowerKeySuppressed
  }

  private func openPrivacyPane(_ pane: String) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private var selectedBluetoothBridge: XiaomiBluetoothBridge? {
    guard let identifier = settings.selectedRemoteProfile?.bluetoothIdentifier else { return nil }
    return bluetoothBridges[identifier]
  }

  private func startBluetoothConnections() {
    let identifiers = Set(settings.remoteDeviceProfiles.compactMap(\.bluetoothIdentifier))
    for identifier in identifiers where bluetoothBridges[identifier] == nil {
      let bridge = XiaomiBluetoothBridge(
        settings: settings,
        delegate: self,
        targetIdentifier: identifier
      )
      bluetoothBridges[identifier] = bridge
      bridge.start()
    }
    startBluetoothDiscoveryIfNeeded()
  }

  private func startBluetoothDiscoveryIfNeeded() {
    guard started, discoveryBluetoothBridge == nil else { return }
    let bridge = XiaomiBluetoothBridge(
      settings: settings,
      delegate: self,
      excludedIdentifiers: { [weak self] in
        guard let self else { return [] }
        return Set(self.bluetoothBridges.keys)
      }
    )
    discoveryBluetoothBridge = bridge
    bridge.start()
  }

  private func registerBluetoothBridgeIfNeeded(_ bridge: XiaomiBluetoothBridge) -> UUID? {
    guard let identifier = bluetoothIdentifier(for: bridge) else { return nil }
    let profileID =
      settings.profileID(forBluetoothIdentifier: identifier)
      ?? settings.registerBluetoothRemote(identifier: identifier)
    if discoveryBluetoothBridge === bridge {
      discoveryBluetoothBridge = nil
      bluetoothBridges[identifier] = bridge
      startBluetoothDiscoveryIfNeeded()
    } else if bluetoothBridges[identifier] == nil {
      bluetoothBridges[identifier] = bridge
    }
    return profileID
  }

  private func bluetoothIdentifier(for bridge: XiaomiBluetoothBridge) -> UUID? {
    bridge.deviceIdentifier ?? bluetoothBridges.first(where: { $0.value === bridge })?.key
  }

  private func remoteProfileID(for bridge: XiaomiBluetoothBridge) -> UUID? {
    guard let identifier = bluetoothIdentifier(for: bridge) else { return nil }
    return settings.profileID(forBluetoothIdentifier: identifier)
      ?? settings.registerBluetoothRemote(identifier: identifier)
  }

  private func activateRemoteProfile(for bridge: XiaomiBluetoothBridge) -> UUID? {
    guard let profileID = registerBluetoothBridgeIfNeeded(bridge) else { return nil }
    selectRemoteProfile(profileID)
    return profileID
  }

  private func refreshBluetoothPresentation() {
    let allStates = bluetoothBridgeStates.values
    state.connectedRemoteProfileIDs = Set(
      bluetoothBridges.compactMap { identifier, bridge in
        guard let profileID = settings.profileID(forBluetoothIdentifier: identifier),
          let bridgeState = bluetoothBridgeStates[ObjectIdentifier(bridge)],
          case .ready = bridgeState
        else { return nil }
        return profileID
      })
    state.isConnected = allStates.contains { if case .ready = $0 { true } else { false } }
    if let selectedBluetoothBridge,
      let bridgeState = bluetoothBridgeStates[ObjectIdentifier(selectedBluetoothBridge)]
    {
      state.connectionStatus = bridgeState.message
    } else if let ready = allStates.first(where: { if case .ready = $0 { true } else { false } }) {
      state.connectionStatus = ready.message
    } else if let bridgeState = allStates.first {
      state.connectionStatus = bridgeState.message
    } else {
      state.connectionStatus = LocalizedMessage("connection.status.searching")
    }
  }

  func bluetoothBridge(
    _ bridge: XiaomiBluetoothBridge,
    didChange bridgeState: BluetoothBridgeState
  ) {
    bluetoothBridgeStates[ObjectIdentifier(bridge)] = bridgeState
    if case .ready = bridgeState {
      _ = registerBluetoothBridgeIfNeeded(bridge)
      voiceFnTapSession.resume()
      applyHIDSettings()
      _ = ensureVirtualAudioOutputReady(reason: "bluetooth_ready")
    } else {
      if let profileID = remoteProfileID(for: bridge) {
        state.remoteBatteryLevels.removeValue(forKey: profileID)
        state.remotePowerStates.removeValue(forKey: profileID)
      }
      if bluetoothIdentifier(for: bridge) == activeBluetoothVoiceDeviceIdentifier {
        bluetoothVoiceActive = false
        activeBluetoothVoiceDeviceIdentifier = nil
        endVoiceSessionIfNeeded(flushAudio: false)
      }
    }
    refreshBluetoothPresentation()
    if !state.isConnected {
      voiceFnTapSession.suspend()
    }
  }

  func bluetoothBridgeDidStartVoice(_ bridge: XiaomiBluetoothBridge) {
    guard let identifier = bridge.deviceIdentifier else { return }
    let profileID = activateRemoteProfile(for: bridge)
    if let activeBluetoothVoiceDeviceIdentifier,
      activeBluetoothVoiceDeviceIdentifier != identifier
    {
      _ = bridge.requestMicrophoneClose()
      AppLogger.shared.write("ATVV STREAM rejected_busy")
      return
    }
    guard ensureVirtualAudioOutputReady(reason: "bluetooth_voice_start") else {
      _ = bridge.requestMicrophoneClose()
      AppLogger.shared.write("ATVV STREAM rejected_audio_output")
      return
    }
    activeBluetoothVoiceDeviceIdentifier = identifier
    bluetoothVoiceActive = true
    bluetoothVoiceTraceCounter &+= 1
    activeBluetoothVoiceTraceID = bluetoothVoiceTraceCounter
    bluetoothVoiceTraceStartedAt = Date()
    bluetoothVoiceTraceModel =
      profileID.flatMap { id in
        settings.remoteDeviceProfiles.first(where: { $0.id == id })?.model
      } ?? .unknown
    bluetoothVoiceDecodedBatchCount = 0
    bluetoothVoiceDecodedSampleCount = 0
    bluetoothVoiceEnqueueFailureCount = 0
    bluetoothVoiceTraceRoute = "none"
    state.currentVoiceSampleCount = 0
    _ = voiceFnTapSession.startVoice()
    beginVoiceSessionIfNeeded()
    AppLogger.shared.write(
      "ATVV STREAM accepted trace=\(bluetoothVoiceTraceCounter) model=\(bluetoothVoiceTraceModel.rawValue)"
    )
  }

  func bluetoothBridgeDidStopVoice(_ bridge: XiaomiBluetoothBridge) {
    guard bridge.deviceIdentifier == activeBluetoothVoiceDeviceIdentifier else { return }
    activeBluetoothVoiceDeviceIdentifier = nil
    bluetoothVoiceActive = false
    let handledByFnTapMode = voiceFnTapSession.stopVoice()
    let shouldFlush = BluetoothVoiceStopPolicy.shouldFlushAudio(
      handledByFnTapMode: handledByFnTapMode
    )
    let durationMilliseconds =
      bluetoothVoiceTraceStartedAt.map {
        max(0, Int(Date().timeIntervalSince($0) * 1_000))
      } ?? 0
    AppLogger.shared.write(
      "ATVV STREAM summary trace=\(activeBluetoothVoiceTraceID ?? 0) "
        + "model=\(bluetoothVoiceTraceModel.rawValue) duration_ms=\(durationMilliseconds) "
        + "batches=\(bluetoothVoiceDecodedBatchCount) samples=\(bluetoothVoiceDecodedSampleCount) "
        + "enqueue_failures=\(bluetoothVoiceEnqueueFailureCount) route=\(bluetoothVoiceTraceRoute)"
    )
    activeBluetoothVoiceTraceID = nil
    bluetoothVoiceTraceStartedAt = nil
    endVoiceSessionIfNeeded(flushAudio: shouldFlush)
  }

  func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDecode samples: [Int16]) {
    guard bridge.deviceIdentifier == activeBluetoothVoiceDeviceIdentifier else { return }
    let handledByFnTapMode = voiceFnTapSession.receive(samples)
    let enqueued = handledByFnTapMode || audioOutput.enqueue(samples: samples)
    bluetoothVoiceDecodedBatchCount += 1
    bluetoothVoiceDecodedSampleCount += samples.count
    state.currentVoiceSampleCount &+= UInt64(samples.count)
    if !enqueued { bluetoothVoiceEnqueueFailureCount += 1 }
    bluetoothVoiceTraceRoute = handledByFnTapMode ? "fn_tap" : "virtual_audio"
  }

  func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateBatteryLevel level: Int?) {
    guard let profileID = remoteProfileID(for: bridge) else { return }
    if let level {
      state.remoteBatteryLevels[profileID] = min(100, max(0, level))
    } else {
      state.remoteBatteryLevels.removeValue(forKey: profileID)
    }
  }

  func bluetoothBridge(
    _ bridge: XiaomiBluetoothBridge,
    didIdentifyRemoteModel model: XiaomiRemoteModel
  ) {
    guard let profileID = remoteProfileID(for: bridge) else { return }
    settings.updateRemoteProfileModel(profileID, model: model)
  }

  func bluetoothBridge(
    _ bridge: XiaomiBluetoothBridge,
    didUpdatePowerState powerState: RemotePowerState?
  ) {
    guard let profileID = remoteProfileID(for: bridge) else { return }
    if let powerState {
      state.remotePowerStates[profileID] = powerState
    } else {
      state.remotePowerStates.removeValue(forKey: profileID)
    }
  }

  private func beginVoiceSessionIfNeeded() {
    guard !state.isStreaming else { return }
    cancelTestToneIfNeeded(
      statusMessage: LocalizedMessage("audio.test_tone.blocked_voice_active"),
      logReason: "voice_start"
    )
    state.isStreaming = true
  }

  private func endVoiceSessionIfNeeded(flushAudio: Bool) {
    guard !bluetoothVoiceActive, state.isStreaming else { return }
    state.isStreaming = false
    if flushAudio {
      audioOutput.endSession()
    }
  }
}
