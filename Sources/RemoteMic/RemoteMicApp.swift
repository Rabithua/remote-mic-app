import AppKit
import Observation
import SwiftUI

@main
struct RemoteMicApp: App {
  @NSApplicationDelegateAdaptor(RemoteMicAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
@Observable
final class SettingsNavigationModel {
  var selection: SettingsPage = .connection
}

@MainActor
final class RemoteMicAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let settings = AppSettings()
  private let runtimeState = AppRuntimeState()
  private lazy var model = BridgeAppModel(settings: settings, state: runtimeState)
  private lazy var localization = LocalizationStore(settings: settings)
  private let loginItem = LoginItemManager()
  private let navigation = SettingsNavigationModel()

  private var statusItem: NSStatusItem?
  private var statusMenu = NSMenu()
  private var settingsWindow: NSWindow?
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

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === statusMenu else { return }
    rebuildStatusMenu()
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = item.button else { return }
    if let image = NSImage(named: "StatusIconTemplate") {
      image.isTemplate = true
      button.image = image
    } else {
      button.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: nil)
    }
    button.toolTip = localization.text("app.name")
    button.target = self
    button.action = #selector(showStatusMenu(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusMenu.delegate = self
    statusItem = item
  }

  @objc private func showStatusMenu(_ sender: NSStatusBarButton) {
    rebuildStatusMenu()
    statusMenu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: sender.bounds.height + 3),
      in: sender
    )
  }

  private func rebuildStatusMenu() {
    statusMenu.removeAllItems()
    addStatusItem(
      title: "\(localization.text("connection.status.bluetooth_title")) · "
        + runtimeState.connectionStatus.text(using: localization),
      healthy: runtimeState.isConnected
    )
    addStatusItem(
      title: "\(localization.text("audio.status.title")) · "
        + runtimeState.audioStatus.text(using: localization),
      healthy: runtimeState.isAudioOutputReady
    )
    addStatusItem(
      title: "HID · \(runtimeState.hidStatus.text(using: localization))",
      healthy: HIDPermissionSnapshot.current.inputMonitoringGranted
        && HIDPermissionSnapshot.current.accessibilityGranted
    )
    statusMenu.addItem(.separator())

    addActionItem(
      title: localization.text("connection.action.reconnect"),
      action: #selector(reconnect)
    )

    let quickMapping = NSMenuItem(
      title: localization.text("menu.button_mapping.title"),
      action: nil,
      keyEquivalent: ""
    )
    quickMapping.submenu = StatusBarButtonMappingMenuFactory.makeMenu(
      settings: settings,
      connectedRemoteProfileIDs: runtimeState.connectedRemoteProfileIDs,
      localization: localization,
      target: self,
      actions: StatusBarButtonMappingMenuActions(
        toggleMapping: #selector(toggleMapping),
        selectRemoteProfile: #selector(selectRemoteProfile(_:)),
        selectButtonAction: #selector(selectButtonAction(_:)),
        openFullEditor: #selector(openMappingSettings)
      )
    )
    statusMenu.addItem(quickMapping)

    addActionItem(
      title: localization.text("menu.open_settings"),
      action: #selector(openSettingsFromMenu),
      keyEquivalent: ","
    )
    statusMenu.addItem(.separator())

    let loginTitle = localization.text("menu.launch_at_login")
    let login = addActionItem(title: loginTitle, action: #selector(toggleLoginItem))
    login.state = loginItem.isEnabled ? .on : .off
    if loginItem.state == .requiresApproval {
      addActionItem(
        title: localization.text("menu.login_item.open_settings"),
        action: #selector(openLoginItemSettings)
      )
    } else if case .failed = loginItem.state {
      addActionItem(
        title: localization.text("menu.login_item.failed"),
        action: #selector(openLoginItemSettings)
      )
    }

    let languageItem = NSMenuItem(
      title: localization.text("menu.language"),
      action: nil,
      keyEquivalent: ""
    )
    languageItem.submenu = makeLanguageMenu()
    statusMenu.addItem(languageItem)
    addActionItem(
      title: localization.text("menu.open_log_folder"),
      action: #selector(openLogs)
    )

    statusMenu.addItem(.separator())
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "Development"
    let versionItem = NSMenuItem(
      title: "\(localization.text("app.name")) \(version)",
      action: nil,
      keyEquivalent: ""
    )
    versionItem.isEnabled = false
    statusMenu.addItem(versionItem)
    addActionItem(
      title: localization.text("common.action.quit"),
      action: #selector(quit),
      keyEquivalent: "q"
    )
  }

  private func addStatusItem(title: String, healthy: Bool) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.image = NSImage(
      systemSymbolName: healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
      accessibilityDescription: nil
    )
    item.isEnabled = false
    statusMenu.addItem(item)
  }

  @discardableResult
  private func addActionItem(
    title: String,
    action: Selector,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    statusMenu.addItem(item)
    return item
  }

  private func makeLanguageMenu() -> NSMenu {
    let menu = NSMenu()
    for language in AppLanguage.allCases {
      let title =
        language == .system
        ? localization.text("language.system")
        : language.nativeDisplayName
      let item = NSMenuItem(
        title: title,
        action: #selector(selectLanguage(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = language.rawValue
      item.state = settings.applicationLanguage == language ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  @objc private func reconnect() {
    model.reconnect()
    model.refreshAudioDevices()
    model.refreshHIDAfterPermissionChange()
  }

  @objc private func toggleMapping() {
    settings.customMappingEnabled.toggle()
    model.applyHIDSettings()
  }

  @objc private func selectRemoteProfile(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
      let id = UUID(uuidString: raw)
    else { return }
    model.selectRemoteProfile(id)
  }

  @objc private func selectButtonAction(_ sender: NSMenuItem) {
    guard let selection = sender.representedObject as? StatusBarButtonActionSelection else {
      return
    }
    selection.apply(to: settings)
    model.applyHIDSettings()
  }

  @objc private func openMappingSettings() {
    openSettings(page: .mapping)
  }

  @objc private func openSettingsFromMenu() {
    openSettings(page: navigation.selection)
  }

  @objc private func toggleLoginItem() {
    loginItem.setEnabled(!loginItem.isEnabled)
    if loginItem.state == .requiresApproval {
      loginItem.openSystemSettings()
    }
  }

  @objc private func openLoginItemSettings() {
    loginItem.openSystemSettings()
  }

  @objc private func selectLanguage(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
      let language = AppLanguage(rawValue: raw)
    else { return }
    localization.select(language)
    statusItem?.button?.toolTip = localization.text("app.name")
  }

  @objc private func openLogs() {
    model.openLogFolder()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
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
