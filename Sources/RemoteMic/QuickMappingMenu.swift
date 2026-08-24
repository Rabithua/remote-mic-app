import AppKit
import SwiftUI

struct QuickMappingMenu: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel
  let onOpenEditor: () -> Void

  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "keyboard")
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(localization.text("menu.button_mapping.title"))
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, SayAllDesign.rowHorizontalPadding)
    .padding(.vertical, 8)
    .frame(width: SayAllDesign.statusPanelWidth, alignment: .leading)
    .contentShape(Rectangle())
    .overlay {
      QuickMappingMenuPresenter(
        accessibilityLabel: localization.text("menu.button_mapping.title"),
        makeMenu: makeMenu
      )
    }
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    menu.addItem(
      actionItem(
        localization.text("button_mapping.toggle.enabled"),
        state: settings.customMappingEnabled ? .on : .off
      ) {
        settings.customMappingEnabled.toggle()
        model.applyHIDSettings()
      }
    )
    menu.addItem(remoteSelectorItem())
    menu.addItem(.separator())

    for button in RemoteButton.allCases {
      menu.addItem(buttonMenuItem(button))
    }

    menu.addItem(.separator())
    menu.addItem(
      actionItem(localization.text("menu.button_mapping.open_full_editor")) {
        onOpenEditor()
      }
    )
    return menu
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
      let name = ButtonMappingPresentation.remoteDisplayName(
        profile,
        among: settings.remoteDeviceProfiles,
        using: localization
      )
      submenu.addItem(
        actionItem(
          name,
          state: settings.selectedRemoteProfileID == profile.id ? .on : .off
        ) {
          model.selectRemoteProfile(profile.id)
        }
      )
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
    let title = String(
      format: localization.text("menu.button_mapping.button_format"),
      locale: localization.locale,
      arguments: [button.shortLabel(using: localization), summary]
    )

    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    submenu.addItem(actionItem(.disabled, for: button, configured: configured))
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
        groupMenu.addItem(actionItem(action, for: button, configured: configured))
      }
      groupItem.submenu = groupMenu
      submenu.addItem(groupItem)
    }
    item.submenu = submenu
    return item
  }

  private func actionItem(
    _ action: ButtonAction,
    for button: RemoteButton,
    configured: ConfiguredButtonAction
  ) -> NSMenuItem {
    let title =
      action == .disabled
      ? localization.text("button_mapping.action.disable_switch")
      : action.displayName(using: localization)
    return actionItem(title, state: configured.action == action ? .on : .off) {
      settings.setAction(action, for: button, trigger: .singleClick)
      model.applyHIDSettings()
    }
  }

  private func actionItem(
    _ title: String,
    state: NSControl.StateValue = .off,
    action: @escaping @MainActor () -> Void
  ) -> NSMenuItem {
    let target = QuickMappingMenuActionTarget(action: action)
    let item = NSMenuItem(
      title: title,
      action: #selector(QuickMappingMenuActionTarget.perform(_:)),
      keyEquivalent: ""
    )
    item.target = target
    item.representedObject = target
    item.state = state
    item.isEnabled = true
    return item
  }
}

@MainActor
private final class QuickMappingMenuActionTarget: NSObject {
  let action: @MainActor () -> Void

  init(action: @escaping @MainActor () -> Void) {
    self.action = action
  }

  @objc func perform(_ sender: NSMenuItem) {
    action()
  }
}
