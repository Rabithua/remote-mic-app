#if DEBUG
  import AppKit

  /// Explicit integration runner: real HID parsing, timers and CGEvent output,
  /// but isolated preferences and no Bluetooth/audio/device-manager startup.
  @MainActor
  enum TVHoldVerification {
    static func run() {
      let app = NSApplication.shared
      app.setActivationPolicy(.accessory)
      guard KeyboardInjector.isAccessibilityTrusted,
        !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
      else {
        emit("VERIFY unavailable: permission missing or Command already held")
        return
      }
      let original = NSWorkspace.shared.frontmostApplication
      let suite = "SayAll.TVHoldVerification.\(UUID().uuidString)"
      guard let defaults = UserDefaults(suiteName: suite) else { return }
      let settings = AppSettings(defaults: defaults)
      let profile = settings.registerHIDRemote(fingerprint: suite)
      settings.selectRemoteProfile(profile)
      settings.customMappingEnabled = true
      settings.setAction(.appSwitcher, for: .tv)
      settings.setAction(.browseApps, for: .tv, trigger: .longPress)
      let session = AppSwitcherSession(diagnosticLogger: emit)
      let monitor = HIDRemoteMonitor(
        settings: settings, profileID: profile, appSwitcher: session,
        runtimePermissions: { KeyboardInjector.isAccessibilityTrusted },
        actionPerformer: { _, _, configured in
          guard configured.action == .appSwitcher else { return false }
          return KeyboardInjector.send(.appSwitcher)
        }, diagnosticLogger: emit)
      monitor.connectSimulatedDevice(fingerprint: suite, profileID: profile)
      var busy = false
      func report(_ button: RemoteButton?) {
        let usage = button?.hidUsage ?? 0
        monitor.handleSimulatedReport(
          reportID: 1, data: Data([UInt8(usage & 0xFF), UInt8(usage >> 8)]))
      }
      func describe(_ stage: String) {
        let front = NSWorkspace.shared.frontmostApplication
        emit(
          "VERIFY stage=\(stage) active=\(session.isActive) front=\(front?.bundleIdentifier ?? "none") pid=\(front?.processIdentifier ?? 0) command=\(CGEventSource.keyState(.combinedSessionState, key: 55)) tab=\(CGEventSource.keyState(.combinedSessionState, key: 48))"
        )
      }
      func cleanup() {
        monitor.stop()
        session.cancel()
        FileHandle.standardInput.readabilityHandler = nil
        defaults.removePersistentDomain(forName: suite)
        original?.activate()
        app.terminate(nil)
      }
      FileHandle.standardInput.readabilityHandler = { handle in
        let data = handle.availableData
        let commands = String(data: data, encoding: .utf8) ?? "quit"
        Task { @MainActor in
          if data.isEmpty {
            cleanup()
            return
          }
          for line in commands.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            if fields.first == "quit" {
              cleanup()
              return
            }
            guard !busy, fields.count == 2,
              ["cycle", "cancel", "disconnect"].contains(String(fields[0])),
              let duration = Int(fields[1]), (50...5_000).contains(duration)
            else {
              describe("idle_or_invalid_command")
              continue
            }
            busy = true
            monitor.connectSimulatedDevice(fingerprint: suite, profileID: profile)
            let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let mode = String(fields[0])
            describe("before_\(mode)_\(duration)ms")
            report(.tv)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(duration)) {
              if mode == "disconnect" {
                monitor.disconnectSimulatedDevice()
              } else if mode == "cancel" {
                report(.back)
                report(nil)
              } else {
                report(nil)
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                describe("after_\(mode)_\(duration)ms")
                let unchanged = NSWorkspace.shared.frontmostApplication?.processIdentifier == before
                emit("VERIFY front_unchanged=\(unchanged) mode=\(mode)")
                busy = false
              }
            }
          }
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(180)) { cleanup() }
      emit("VERIFY ready: cycle <50...5000 ms>, cancel <ms>, disconnect <ms>, quit")
      withExtendedLifetime(monitor) { app.run() }
    }

    private static func emit(_ message: String) {
      print(message)
      fflush(stdout)
    }
  }
#endif
