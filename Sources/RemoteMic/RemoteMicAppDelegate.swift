import AppKit
import SwiftUI

@MainActor
final class RemoteMicAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let settings = AppSettings()
  private let runtimeState = AppRuntimeState()
  private lazy var model = BridgeAppModel(settings: settings, state: runtimeState)
  private lazy var localization = LocalizationStore(settings: settings)
  private let loginItem = LoginItemManager()
  private let navigation = SettingsNavigationModel()

  private var statusItem: NSStatusItem?
  private let statusPopover = NSPopover()
  private var settingsWindow: NSWindow?
  private var workspaceObservers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()
    configureStatusPopover()
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
    button.target = self
    button.action = #selector(toggleStatusPanel(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem = item
  }

  private func configureStatusPopover() {
    let rootView = StatusPanelView(
      settings: settings,
      state: runtimeState,
      model: model,
      loginItem: loginItem,
      onOpenSettings: { [weak self] page in
        self?.closeStatusPanel()
        self?.openSettings(page: page)
      },
      onOpenLoginItemSettings: { [weak self] in
        self?.loginItem.openSystemSettings()
      },
      onQuit: { NSApp.terminate(nil) }
    )
    .environmentObject(localization)

    statusPopover.behavior = .transient
    statusPopover.animates = true
    statusPopover.contentSize = NSSize(
      width: SayAllDesign.statusPanelWidth,
      height: SayAllDesign.statusPanelHeight
    )
    statusPopover.contentViewController = NSHostingController(rootView: rootView)
    statusPopover.delegate = self
  }

  @objc private func toggleStatusPanel(_ sender: NSStatusBarButton) {
    if statusPopover.isShown {
      closeStatusPanel()
    } else {
      loginItem.refresh()
      model.refreshHIDAfterPermissionChange()
      statusPopover.show(
        relativeTo: sender.bounds,
        of: sender,
        preferredEdge: .minY
      )
    }
  }

  private func closeStatusPanel() {
    statusPopover.performClose(nil)
  }

  private func openSettings(page: SettingsPage) {
    navigation.selection = page
    if settingsWindow == nil {
      let rootView = SettingsView(
        settings: settings,
        state: runtimeState,
        model: model,
        navigation: navigation
      )
      .environmentObject(localization)
      let controller = NSHostingController(rootView: rootView)
      let window = NSWindow(contentViewController: controller)
      window.title = localization.text("app.name")
      window.setContentSize(NSSize(width: 820, height: 620))
      window.minSize = NSSize(width: 760, height: 540)
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
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
