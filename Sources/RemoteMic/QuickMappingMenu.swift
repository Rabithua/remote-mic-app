import SwiftUI

struct QuickMappingMenu: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel
  let onOpenEditor: () -> Void

  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    Menu {
      Button {
        settings.customMappingEnabled.toggle()
        model.applyHIDSettings()
      } label: {
        if settings.customMappingEnabled {
          Label(
            localization.text("button_mapping.toggle.enabled"),
            systemImage: "checkmark"
          )
        } else {
          Text(localization.text("button_mapping.toggle.enabled"))
        }
      }

      remoteSelector
      Divider()

      ForEach(RemoteButton.allCases) { button in
        buttonMenu(button)
      }

      Divider()
      Button(localization.text("menu.button_mapping.open_full_editor")) {
        onOpenEditor()
      }
    } label: {
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
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
  }

  @ViewBuilder
  private var remoteSelector: some View {
    let connectedProfiles = settings.remoteDeviceProfiles.filter {
      state.connectedRemoteProfileIDs.contains($0.id)
    }
    if connectedProfiles.isEmpty {
      Text(localization.text("menu.button_mapping.no_remote"))
    } else {
      Menu(localization.text("menu.button_mapping.remote")) {
        ForEach(connectedProfiles) { profile in
          Button {
            model.selectRemoteProfile(profile.id)
          } label: {
            let name = ButtonMappingPresentation.remoteDisplayName(
              profile,
              among: settings.remoteDeviceProfiles,
              using: localization
            )
            if settings.selectedRemoteProfileID == profile.id {
              Label(name, systemImage: "checkmark")
            } else {
              Text(name)
            }
          }
        }
      }
    }
  }

  private func buttonMenu(_ button: RemoteButton) -> some View {
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

    return Menu(title) {
      actionButton(.disabled, for: button, configured: configured)
      Divider()

      let groups = ButtonMappingPresentation.actionGroups(
        installedBundleIdentifiers: PresetApplication.installedBundleIdentifiers,
        currentAction: configured.action,
        hasConfiguredShortcut: configured.shortcut != nil,
        hasConfiguredApplication: customApplicationName != nil
      )
      ForEach(groups, id: \.category) { group in
        Menu(localization.text(group.category.localizationKey)) {
          ForEach(group.actions) { action in
            actionButton(action, for: button, configured: configured)
          }
        }
      }
    }
  }

  private func actionButton(
    _ action: ButtonAction,
    for button: RemoteButton,
    configured: ConfiguredButtonAction
  ) -> some View {
    Button {
      settings.setAction(action, for: button, trigger: .singleClick)
      model.applyHIDSettings()
    } label: {
      let title =
        action == .disabled
        ? localization.text("button_mapping.action.disable_switch")
        : action.displayName(using: localization)
      if configured.action == action {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }
}
