import AppKit
import SwiftUI

@MainActor
final class RemoteMicAppDelegate: NSObject, NSApplicationDelegate {
  private let settings = AppSettings()
  private let runtimeState = AppRuntimeState()
  private lazy var model = BridgeAppModel(settings: settings, state: runtimeState)
  private lazy var localization = LocalizationStore(settings: settings)
  private let loginItem = LoginItemManager()
  private let navigation = SettingsNavigationModel()

  private var statusItem: NSStatusItem?
  private var statusMenuController: NativeStatusMenuController?
  private var settingsWindow: KeyableSettingsPanel?
  private var workspaceObservers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()
    observeSystemLifecycle()
    model.startIfNeeded()
    if !settings.setupHasPresented {
      settings.markSetupPresented()
      openSettings(page: .connection)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    workspaceObservers.removeAll()
    model.stop()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag { openSettings(page: navigation.selection) }
    return true
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = item.button else { return }
    if let image = NSImage(named: "StatusIconTemplate") {
      image.isTemplate = true
      button.image = image
    } else {
      button.image = NSImage(
        systemSymbolName: "waveform.badge.mic",
        accessibilityDescription: nil
      )
    }
    button.toolTip = localization.text("app.name")

    let controller = NativeStatusMenuController(
      settings: settings,
      state: runtimeState,
      model: model,
      loginItem: loginItem,
      localization: localization,
      onOpenSettings: { [weak self] page in
        self?.openSettings(page: page)
      },
      onLanguageChange: { [weak self] in
        self?.statusItem?.button?.toolTip = self?.localization.text("app.name")
      },
      onQuit: { NSApp.terminate(nil) }
    )
    item.menu = controller.menu
    statusMenuController = controller
    statusItem = item
  }

  private func openSettings(page: SettingsPage) {
    navigation.selection = page
    if settingsWindow == nil {
      let rootView = SettingsView(
        settings: settings,
        state: runtimeState,
        model: model,
        navigation: navigation,
        onClose: { [weak self] in
          self?.settingsWindow?.orderOut(nil)
        }
      )
      .environmentObject(localization)
      let controller = NSHostingController(rootView: rootView)
      let panel = KeyableSettingsPanel(
        contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
        styleMask: [.borderless, .nonactivatingPanel, .resizable],
        backing: .buffered,
        defer: false
      )
      panel.contentViewController = controller
      panel.minSize = NSSize(width: 760, height: 540)
      panel.setContentSize(NSSize(width: 820, height: 620))
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.hidesOnDeactivate = false
      panel.isMovableByWindowBackground = true
      panel.level = .floating
      panel.isReleasedWhenClosed = false
      panel.center()
      settingsWindow = panel
    }
    settings.markSetupPresented()
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  private func observeSystemLifecycle() {
    let center = NSWorkspace.shared.notificationCenter
    let events: [(Notification.Name, SystemAudioLifecycleEvent)] = [
      (NSWorkspace.screensDidSleepNotification, .screenDidSleep),
      (NSWorkspace.screensDidWakeNotification, .screenDidWake),
      (NSWorkspace.sessionDidResignActiveNotification, .sessionDidResignActive),
      (NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive),
      (NSWorkspace.willSleepNotification, .systemWillSleep),
      (NSWorkspace.didWakeNotification, .systemDidWake),
    ]
    workspaceObservers = events.map { name, event in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.model.handleSystemAudioLifecycle(event)
        }
      }
    }
  }
}
