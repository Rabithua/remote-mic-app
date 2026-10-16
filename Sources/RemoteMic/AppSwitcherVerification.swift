#if DEBUG
  import AppKit

  /// Opt-in manual integration runner. Replays HID reports through the real monitor,
  /// session and AppKit panel, using isolated preferences and no physical device.
  @MainActor
  enum AppSwitcherVerification {
    static func run() {
      let app = NSApplication.shared
      app.setActivationPolicy(.accessory)
      guard KeyboardInjector.isAccessibilityTrusted else {
        print("VERIFY unavailable: accessibility not authorized")
        return
      }
      let original = NSWorkspace.shared.frontmostApplication
      let suite = "SayAll.AppSwitcherVerification.\(UUID().uuidString)"
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
        actionPerformer: { _, _, _ in
          emit("VERIFY FAIL unexpected ordinary mapping")
          return false
        }, diagnosticLogger: emit)
      monitor.connectSimulatedDevice(fingerprint: suite, profileID: profile)
      func report(_ button: RemoteButton?) {
        let usage = button?.hidUsage ?? 0
        monitor.handleSimulatedReport(
          reportID: 1, data: Data([UInt8(usage & 0xFF), UInt8(usage >> 8)]))
      }
      func describe(_ stage: String) {
        emit(
          "VERIFY stage=\(stage) active=\(session.isActive) index=\(session.selectedIndex) count=\(session.applications.count) selected=\(session.selectedApplication?.bundleIdentifier ?? "none") front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") command=\(CGEventSource.keyState(.combinedSessionState, key: 55))"
        )
      }
      func cleanup() {
        monitor.stop()
        session.cancel()
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
          for command in commands.split(whereSeparator: \.isNewline) {
            switch command {
            case "open":
              report(.tv)
              DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(650)) {
                report(nil)
                describe("opened")
              }
            case "left", "right", "ok", "back":
              let button: RemoteButton =
                command == "left"
                ? .left : command == "right" ? .right : command == "ok" ? .ok : .back
              let target = session.selectedApplication
              let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
              report(button)
              report(nil)
              let stage = String(command)
              DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) {
                describe(stage)
                if button == .ok {
                  emit(
                    "VERIFY activation_matches=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == target?.processIdentifier)"
                  )
                } else if button == .back {
                  emit(
                    "VERIFY cancellation_preserves_front=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == before)"
                  )
                }
              }
            case "quit": cleanup()
            default: describe("status")
            }
          }
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(180)) { cleanup() }
      emit("VERIFY ready commands=open,left,right,ok,back,status,quit; no live Bluetooth or audio")
      withExtendedLifetime(monitor) { app.run() }
    }

    private static func emit(_ message: String) {
      print(message)
      fflush(stdout)
    }
  }
#endif
