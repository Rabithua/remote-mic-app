import SwiftUI

struct SettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel
  @Bindable var navigation: SettingsNavigationModel
  let onClose: () -> Void

  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    VStack(spacing: 0) {
      SettingsWindowHeader(
        title: localization.text("settings.window.title"),
        closeLabel: localization.text("common.action.close"),
        onClose: close
      )
      Divider()

      HStack(spacing: 0) {
        sidebar
        Divider()
        detail
      }
    }
    .frame(minWidth: 760, minHeight: 540)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      HStack(spacing: 9) {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(width: 28, height: 28)
          .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
        Text(localization.text("app.name"))
          .font(.headline)
        Spacer(minLength: 0)
      }
      .padding(14)

      VStack(spacing: 3) {
        ForEach(SettingsPage.allCases) { page in
          SettingsSidebarButton(
            title: localization.text(page.titleKey),
            systemImage: page.systemImage,
            isSelected: navigation.selection == page
          ) {
            navigation.selection = page
          }
        }
      }
      .padding(.horizontal, 8)

      Spacer(minLength: 12)
    }
    .frame(width: SayAllDesign.settingsSidebarWidth)
    .background(.quinary.opacity(0.45))
  }

  @ViewBuilder
  private var detail: some View {
    switch navigation.selection {
    case .connection:
      ConnectionAudioSettingsView(settings: settings, state: state, model: model)
    case .mapping:
      ButtonMappingSettingsView(settings: settings, state: state, model: model)
    case .permissions:
      PermissionSettingsView(model: model)
    }
  }

  private func close() {
    settings.completeSetup()
    onClose()
  }
}
