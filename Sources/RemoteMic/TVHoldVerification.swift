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
      let replayNativeEvents = CommandLine.arguments.contains("--with-native-tv-events")
      let suppressor = KeyboardEventSuppressor()
      if replayNativeEvents, !suppressor.start() {
        defaults.removePersistentDomain(forName: suite)
        emit("VERIFY unavailable: native event suppressor could not start")
        return
      }
      var sandbox: NSWindow?
      if replayNativeEvents {
        // The sink must be a real foreground app, not an accessory window
        // receiving background accessibility clicks. This is DEBUG-only.
        app.setActivationPolicy(.regular)
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 440, height: 140),
          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SayAll Native HID Verification"
        window.isReleasedWhenClosed = false
        let sink = VerificationInputSink(frame: window.contentView!.bounds)
        window.contentView = sink
        let label = NSTextField(
          labelWithString:
            "Native TV replay · isolated test window\nNo user data is opened or saved.")
        label.frame = NSRect(x: 24, y: 44, width: 392, height: 52)
        label.maximumNumberOfLines = 2
        sink.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(sink)
        app.activate(ignoringOtherApps: true)
        sandbox = window
      }
      let monitor = HIDRemoteMonitor(
        settings: settings, profileID: profile, eventSuppressor: suppressor, appSwitcher: session,
        runtimePermissions: { KeyboardInjector.isAccessibilityTrusted },
        actionPerformer: { _, _, configured in
          guard configured.action == .appSwitcher else { return false }
          return KeyboardInjector.send(.appSwitcher)
        }, diagnosticLogger: emit)
      monitor.connectSimulatedDevice(
        fingerprint: suite, profileID: profile, isSeized: !replayNativeEvents)
      var busy = false
      let nativeSource = CGEventSource(stateID: .hidSystemState)
      var nativeTVIsDown = false
      func nativeTV(_ isDown: Bool, repeated: Bool = false) {
        guard replayNativeEvents,
          let event = CGEvent(keyboardEventSource: nativeSource, virtualKey: 10, keyDown: isDown)
        else { return }
        // RC003's measured native TV event uses 0x100 (non-coalesced),
        // with no keyboard modifier; mirror the hardware, not an empty mask.
        event.flags = .maskNonCoalesced
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        // Deliberately not tagged as our synthetic output: exercise the real tap.
        event.post(tap: .cghidEventTap)
        nativeTVIsDown = isDown
      }
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
        if nativeTVIsDown { nativeTV(false) }
        monitor.stop()
        session.cancel()
        suppressor.stop()
        sandbox?.orderOut(nil)
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
            if replayNativeEvents,
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                != ProcessInfo.processInfo.processIdentifier
            {
              emit("VERIFY refused: first click the isolated test window")
              continue
            }
            busy = true
            monitor.connectSimulatedDevice(
              fingerprint: suite, profileID: profile, isSeized: !replayNativeEvents)
            let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let mode = String(fields[0])
            describe("before_\(mode)_\(duration)ms")
            report(.tv)
            if replayNativeEvents {
              nativeTV(true)
              // Include unseized native autorepeat while our private Command is held.
              for delay in stride(from: 700, to: duration, by: 100) {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                  guard session.isActive,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier
                      == ProcessInfo.processInfo.processIdentifier
                  else { return }
                  nativeTV(true, repeated: true)
                }
              }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(duration)) {
              if mode == "disconnect" {
                monitor.disconnectSimulatedDevice()
              } else if mode == "cancel" {
                report(.back)
                report(nil)
              } else {
                report(nil)
              }
              if replayNativeEvents { nativeTV(false) }
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

  @MainActor
  private final class VerificationInputSink: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
      if event.keyCode == 10 { print("VERIFY FAIL native TV event leaked through suppressor") }
    }
  }
#endif
