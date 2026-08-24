import SwiftUI

struct ButtonMappingSettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel

  @EnvironmentObject private var localization: LocalizationStore

  private let gridColumns: [GridItem] = [
    GridItem(.fixed(82), spacing: 8, alignment: .leading),
    GridItem(.flexible(minimum: 120), spacing: 8),
    GridItem(.flexible(minimum: 120), spacing: 8),
    GridItem(.flexible(minimum: 120), spacing: 8),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SettingsPageHeader(
          title: localization.text("button_mapping.page.title"),
          subtitle: localization.text("button_mapping.page.subtitle.compact")
        )

        SettingsSection(localization.text("settings.section.buttons")) {
          SettingsRow {
            Toggle(
              localization.text("button_mapping.toggle.enabled"),
              isOn: mappingEnabledBinding
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer(minLength: 12)

            if !settings.remoteDeviceProfiles.isEmpty {
              Picker(
                localization.text("menu.button_mapping.remote"),
                selection: selectedRemoteBinding
              ) {
                ForEach(settings.remoteDeviceProfiles) { profile in
                  Text(remoteName(profile)).tag(Optional(profile.id))
                }
              }
              .controlSize(.small)
              .frame(maxWidth: 240)
            }

            Button {
              settings.resetBindings()
              model.applyHIDSettings()
            } label: {
              Text(localization.text("common.action.restore_defaults"))
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .controlSize(.small)
          }

          SettingsDivider(leading: 0)

          LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
            Text(localization.text("button_mapping.grid.button"))
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            ForEach(ButtonTrigger.allCases) { trigger in
              Text(trigger.displayName(using: localization))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ForEach(RemoteButton.allCases) { button in
              Text(button.displayName(using: localization))
                .font(.callout)
                .fontWeight(state.lastRemoteButtonPress == button ? .semibold : .regular)
              ForEach(ButtonTrigger.allCases) { trigger in
                MappingActionControl(
                  button: button,
                  trigger: trigger,
                  settings: settings,
                  onChange: model.applyHIDSettings
                )
              }
            }
          }
          .padding(12)
        }

        if !settings.customApplicationProfiles.isEmpty {
          SettingsSection(localization.text("custom_application.saved.title")) {
            ForEach(settings.customApplicationProfiles) { profile in
              CustomApplicationEditorRow(profile: profile, settings: settings)
                .padding(12)
              if profile.id != settings.customApplicationProfiles.last?.id {
                SettingsDivider(leading: 0)
              }
            }
          }
        }
      }
      .padding(SayAllDesign.contentPadding)
    }
  }

  private var mappingEnabledBinding: Binding<Bool> {
    Binding(
      get: { settings.customMappingEnabled },
      set: { value in
        settings.customMappingEnabled = value
        model.applyHIDSettings()
      }
    )
  }

  private var selectedRemoteBinding: Binding<UUID?> {
    Binding(
      get: { settings.selectedRemoteProfileID },
      set: { id in
        if let id { model.selectRemoteProfile(id) }
      }
    )
  }

  private func remoteName(_ profile: RemoteDeviceProfile) -> String {
    profile.customName.isEmpty
      ? localization.text(profile.displayNameFallbackKey)
      : profile.customName
  }
}
