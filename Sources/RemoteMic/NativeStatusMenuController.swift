import AppKit

@MainActor
final class NativeStatusMenuController: NSObject, NSMenuDelegate {
  let menu = NSMenu()

  private let settings: AppSettings
  private let state: AppRuntimeState
  private let model: BridgeAppModel
  private let loginItem: LoginItemManager
  private let localization: LocalizationStore
  private let onOpenSettings: (SettingsPage) -> Void
  private let onLanguageChange: () -> Void
  private let onQuit: () -> Void

  init(
    settings: AppSettings,
    state: AppRuntimeState,
    model: BridgeAppModel,
    loginItem: LoginItemManager,
    localization: LocalizationStore,
    onOpenSettings: @escaping (SettingsPage) -> Void,
    onLanguageChange: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    self.settings = settings
    self.state = state
    self.model = model
    self.loginItem = loginItem
    self.localization = localization
    self.onOpenSettings = onOpenSettings
    self.onLanguageChange = onLanguageChange
    self.onQuit = onQuit
    super.init()

    menu.autoenablesItems = false
    menu.minimumWidth = 300
    menu.delegate = self
    rebuild()
  }

  func menuWillOpen(_ menu: NSMenu) {
    loginItem.refresh()
    model.refreshHIDAfterPermissionChange()
    rebuild()
  }

  func rebuild() {
    menu.removeAllItems()

    let warnings = runtimeWarnings
    let summary = localization.text(
      warnings.isEmpty
        ? "status_panel.ready"
        : "status_panel.needs_attention"
    )
    menu.addItem(
      .sectionHeader(
        title: formatted(
          "status_menu.summary_format",
          localization.text("app.name"),
          summary
        )
      )
    )

    menu.addItem(
      statusItem(
        entry: .connectionStatus,
        title: state.connectionStatus.text(using: localization),
        symbol: "antenna.radiowaves.left.and.right",
        action: #selector(openConnectionSettings(_:))
      )
    )
    menu.addItem(
      statusItem(
        entry: .audioStatus,
        title: state.audioStatus.text(using: localization),
        symbol: "waveform",
        action: #selector(openConnectionSettings(_:))
      )
    )
    menu.addItem(
      statusItem(
        entry: .hidStatus,
        title: state.hidStatus.text(using: localization),
        symbol: "keyboard",
        action: #selector(openMappingSettings(_:))
      )
    )

    if warnings.contains(.bluetoothPermission)
      || warnings.contains(.inputMonitoringPermission)
      || warnings.contains(.accessibilityPermission)
    {
      menu.addItem(
        actionItem(
          localization.text("status_panel.review_permissions"),
          symbol: "lock.shield",
          action: #selector(openPermissionSettings(_:))
        )
      )
    }

    menu.addItem(.separator())

    menu.addItem(
      identified(
        actionItem(
          localization.text("connection.action.reconnect"),
          symbol: "arrow.clockwise",
          action: #selector(reconnect(_:))
        ),
        as: .reconnect
      )
    )

    let quickMappingItem = NSMenuItem(
      title: localization.text("menu.button_mapping.title"),
      action: nil,
      keyEquivalent: ""
    )
    quickMappingItem.image = symbol("keyboard")
    quickMappingItem.submenu = makeQuickMappingMenu()
    menu.addItem(identified(quickMappingItem, as: .quickMapping))

    menu.addItem(.separator())

    let launchItem = actionItem(
      localization.text("menu.launch_at_login"),
      symbol: "power",
      action: #selector(toggleLaunchAtLogin(_:))
    )
    launchItem.state = loginItem.isEnabled ? .on : .off
    menu.addItem(identified(launchItem, as: .launchAtLogin))

    if loginItem.state == .requiresApproval || isLoginItemFailure {
      menu.addItem(
        actionItem(
          localization.text(
            isLoginItemFailure
              ? "menu.login_item.failed"
              : "menu.login_item.open_settings"
          ),
          symbol: "exclamationmark.triangle",
          action: #selector(openLoginItemSettings(_:))
        )
      )
    }

    let languageItem = NSMenuItem(
      title: localization.text("menu.language"),
      action: nil,
      keyEquivalent: ""
    )
    languageItem.image = symbol("globe")
    languageItem.submenu = makeLanguageMenu()
    menu.addItem(identified(languageItem, as: .language))

    menu.addItem(
      identified(
        actionItem(
          localization.text("menu.open_log_folder"),
          symbol: "doc.text.magnifyingglass",
          action: #selector(openLogFolder(_:))
        ),
        as: .logs
      )
    )

    menu.addItem(.separator())

    let settingsItem = actionItem(
      localization.text("menu.open_settings"),
      symbol: "gearshape",
      action: #selector(openConnectionSettings(_:)),
      keyEquivalent: ","
    )
    menu.addItem(identified(settingsItem, as: .settings))

    let quitItem = actionItem(
      localization.text("common.action.quit"),
      symbol: "xmark",
      action: #selector(quit(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(identified(quitItem, as: .quit))
  }

  private var runtimeWarnings: Set<RuntimeWarning> {
    let permissions = HIDPermissionSnapshot.current
    return RuntimeWarningPolicy.warnings(
      bluetoothGranted: model.bluetoothPermissionGranted,
      inputMonitoringGranted: permissions.inputMonitoringGranted,
      accessibilityGranted: permissions.accessibilityGranted,
      hasConnectedRemote: state.isConnected,
      audioDeviceAvailable: state.isAudioOutputReady
    )
  }

  private var isLoginItemFailure: Bool {
    if case .failed = loginItem.state { return true }
    return false
  }

  private func makeQuickMappingMenu() -> NSMenu {
    let submenu = NSMenu()
    submenu.autoenablesItems = false

    let enabledItem = actionItem(
      localization.text("button_mapping.toggle.enabled"),
      action: #selector(toggleQuickMapping(_:))
    )
    enabledItem.state = settings.customMappingEnabled ? .on : .off
    submenu.addItem(enabledItem)
    submenu.addItem(remoteSelectorItem())
    submenu.addItem(.separator())

    for button in RemoteButton.allCases {
      submenu.addItem(buttonMenuItem(button))
    }

    submenu.addItem(.separator())
    submenu.addItem(
      actionItem(
        localization.text("menu.button_mapping.open_full_editor"),
        action: #selector(openMappingSettings(_:))
      )
    )
    return submenu
  }

  private func remoteSelectorItem() -> NSMenuItem {
    let connectedProfiles = settings.remoteDeviceProfiles.filter {
      state.connectedRemoteProfileIDs.contains($0.id)
    }
    guard !connectedProfiles.isEmpty else {
      let item = NSMenuItem(
        title: localization.text("menu.button_mapping.no_remote"),
        action: nil,
        keyEquivalent: ""
      )
      item.isEnabled = false
      return item
    }

    let item = NSMenuItem(
      title: localization.text("menu.button_mapping.remote"),
      action: nil,
      keyEquivalent: ""
    )
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    for profile in connectedProfiles {
      let profileItem = actionItem(
        ButtonMappingPresentation.remoteDisplayName(
          profile,
          among: settings.remoteDeviceProfiles,
          using: localization
        ),
        action: #selector(selectRemoteProfile(_:))
      )
      profileItem.representedObject = profile.id.uuidString
      profileItem.state = settings.selectedRemoteProfileID == profile.id ? .on : .off
      submenu.addItem(profileItem)
    }
    item.submenu = submenu
    return item
  }

  private func buttonMenuItem(_ button: RemoteButton) -> NSMenuItem {
    let configured = settings.configuredAction(for: button, trigger: .singleClick)
    let customApplicationName = settings.customApplicationProfile(
      id: configured.applicationProfileID
    )?.displayName
    let summary = ButtonMappingPresentation.actionSummary(
      configured: configured,
      customApplicationName: customApplicationName,
      using: localization
    )
    let item = NSMenuItem(
      title: formatted(
        "menu.button_mapping.button_format",
        button.shortLabel(using: localization),
        summary
      ),
      action: nil,
      keyEquivalent: ""
    )
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    submenu.addItem(mappingActionItem(.disabled, for: button, configured: configured))
    submenu.addItem(.separator())

    let groups = ButtonMappingPresentation.actionGroups(
      installedBundleIdentifiers: PresetApplication.installedBundleIdentifiers,
      currentAction: configured.action,
      hasConfiguredShortcut: configured.shortcut != nil,
      hasConfiguredApplication: customApplicationName != nil
    )
    for group in groups {
      let groupItem = NSMenuItem(
        title: localization.text(group.category.localizationKey),
        action: nil,
        keyEquivalent: ""
      )
      let groupMenu = NSMenu()
      groupMenu.autoenablesItems = false
      for action in group.actions {
        groupMenu.addItem(mappingActionItem(action, for: button, configured: configured))
      }
      groupItem.submenu = groupMenu
      submenu.addItem(groupItem)
    }
    item.submenu = submenu
    return item
  }

  private func mappingActionItem(
    _ action: ButtonAction,
    for button: RemoteButton,
    configured: ConfiguredButtonAction
  ) -> NSMenuItem {
    let title =
      action == .disabled
      ? localization.text("button_mapping.action.disable_switch")
      : action.displayName(using: localization)
    let item = actionItem(title, action: #selector(applyQuickMapping(_:)))
    item.representedObject = [button.rawValue, action.rawValue]
    item.state = configured.action == action ? .on : .off
    return item
  }

  private func makeLanguageMenu() -> NSMenu {
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    for language in AppLanguage.allCases {
      let item = actionItem(
        language == .system
          ? localization.text("language.system")
          : language.nativeDisplayName,
        action: #selector(selectLanguage(_:))
      )
      item.representedObject = language.rawValue
      item.state = settings.applicationLanguage == language ? .on : .off
      submenu.addItem(item)
    }
    return submenu
  }

  private func statusItem(
    entry: StatusMenuEntry,
    title: String,
    symbol: String,
    action: Selector
  ) -> NSMenuItem {
    identified(
      actionItem(
        title,
        symbol: symbol,
        action: action
      ),
      as: entry
    )
  }

  private func actionItem(
    _ title: String,
    symbol symbolName: String? = nil,
    action: Selector,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    if let symbolName {
      item.image = symbol(symbolName)
    }
    if !keyEquivalent.isEmpty {
      item.keyEquivalentModifierMask = [.command]
    }
    return item
  }

  private func identified(_ item: NSMenuItem, as entry: StatusMenuEntry) -> NSMenuItem {
    item.identifier = NSUserInterfaceItemIdentifier(entry.rawValue)
    return item
  }

  private func symbol(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    image?.isTemplate = true
    return image
  }

  private func formatted(_ key: String, _ arguments: String...) -> String {
    String(
      format: localization.text(key),
      locale: localization.locale,
      arguments: arguments
    )
  }

  @objc private func reconnect(_ sender: NSMenuItem) {
    model.reconnect()
    model.refreshAudioDevices()
    model.refreshHIDAfterPermissionChange()
  }

  @objc private func toggleQuickMapping(_ sender: NSMenuItem) {
    settings.customMappingEnabled.toggle()
    model.applyHIDSettings()
  }

  @objc private func selectRemoteProfile(_ sender: NSMenuItem) {
    guard
      let rawValue = sender.representedObject as? String,
      let profileID = UUID(uuidString: rawValue)
    else { return }
    model.selectRemoteProfile(profileID)
  }

  @objc private func applyQuickMapping(_ sender: NSMenuItem) {
    guard
      let values = sender.representedObject as? [String],
      values.count == 2,
      let button = RemoteButton(rawValue: values[0]),
      let action = ButtonAction(rawValue: values[1])
    else { return }
    QuickMappingActionSelection(button: button, action: action).apply(to: settings)
    model.applyHIDSettings()
  }

  @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    loginItem.isEnabled.toggle()
  }

  @objc private func selectLanguage(_ sender: NSMenuItem) {
    guard
      let rawValue = sender.representedObject as? String,
      let language = AppLanguage(rawValue: rawValue)
    else { return }
    localization.select(language)
    onLanguageChange()
  }

  @objc private func openConnectionSettings(_ sender: NSMenuItem) {
    onOpenSettings(.connection)
  }

  @objc private func openMappingSettings(_ sender: NSMenuItem) {
    onOpenSettings(.mapping)
  }

  @objc private func openPermissionSettings(_ sender: NSMenuItem) {
    onOpenSettings(.permissions)
  }

  @objc private func openLoginItemSettings(_ sender: NSMenuItem) {
    loginItem.openSystemSettings()
  }

  @objc private func openLogFolder(_ sender: NSMenuItem) {
    model.openLogFolder()
  }

  @objc private func quit(_ sender: NSMenuItem) {
    onQuit()
  }
}
