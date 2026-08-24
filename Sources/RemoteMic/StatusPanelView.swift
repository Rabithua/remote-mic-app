import SwiftUI

struct StatusPanelView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel
  @Bindable var loginItem: LoginItemManager
  let onOpenSettings: (SettingsPage) -> Void
  let onOpenLoginItemSettings: () -> Void
  let onQuit: () -> Void

  @EnvironmentObject private var localization: LocalizationStore

  private var permissionSnapshot: HIDPermissionSnapshot {
    HIDPermissionSnapshot.current
  }

  private var permissionIssueCount: Int {
    [
      model.bluetoothPermissionGranted,
      permissionSnapshot.inputMonitoringGranted,
      permissionSnapshot.accessibilityGranted,
    ].filter { !$0 }.count
  }

  private var warningCount: Int {
    RuntimeWarningPolicy.warnings(
      bluetoothGranted: model.bluetoothPermissionGranted,
      inputMonitoringGranted: permissionSnapshot.inputMonitoringGranted,
      accessibilityGranted: permissionSnapshot.accessibilityGranted,
      hasConnectedRemote: state.isConnected,
      audioDeviceAvailable: state.isAudioOutputReady
    ).count
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView {
        VStack(spacing: 0) {
          VStack(spacing: 10) {
            statusSection
            actionSection
            preferenceSection
          }

          Divider()
          finalActions
        }
      }
    }
    .frame(
      width: SayAllDesign.statusPanelWidth,
      height: SayAllDesign.statusPanelHeight
    )
    .background(.regularMaterial)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "waveform.badge.mic")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 28, height: 28)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))

      VStack(alignment: .leading, spacing: 1) {
        Text(localization.text("app.name"))
          .font(.headline)
        Text(
          localization.text(
            warningCount == 0
              ? "status_panel.ready"
              : "status_panel.needs_attention"
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      Circle()
        .fill(warningCount == 0 ? Color.green : Color.orange)
        .frame(width: 8, height: 8)
        .accessibilityLabel(
          localization.text(
            warningCount == 0
              ? "status_panel.ready"
              : "status_panel.needs_attention"
          )
        )
    }
    .padding(12)
    .background(.quinary)
  }

  private var statusSection: some View {
    SettingsSection(localization.text("status_panel.section.status")) {
      RuntimeStatusRow(
        icon: "antenna.radiowaves.left.and.right",
        title: localization.text("connection.status.bluetooth_title"),
        detail: state.connectionStatus.text(using: localization),
        healthy: state.isConnected
      )
      SettingsDivider()
      RuntimeStatusRow(
        icon: "waveform",
        title: localization.text("audio.status.title"),
        detail: state.audioStatus.text(using: localization),
        healthy: state.isAudioOutputReady
      )
      SettingsDivider()
      RuntimeStatusRow(
        icon: "keyboard",
        title: localization.text("status_panel.hid"),
        detail: state.hidStatus.text(using: localization),
        healthy: permissionSnapshot.inputMonitoringGranted
          && permissionSnapshot.accessibilityGranted
      )

      if permissionIssueCount > 0 {
        SettingsDivider()
        StatusPanelActionButton(
          title: localization.text("status_panel.review_permissions"),
          systemImage: "lock.shield",
          trailingSystemImage: "chevron.right"
        ) {
          onOpenSettings(.permissions)
        }
      }
    }
  }

  private var actionSection: some View {
    SettingsSection(localization.text("status_panel.section.actions")) {
      StatusPanelActionButton(
        title: localization.text("connection.action.reconnect"),
        systemImage: "arrow.clockwise"
      ) {
        model.reconnect()
        model.refreshAudioDevices()
        model.refreshHIDAfterPermissionChange()
      }
      SettingsDivider()
      QuickMappingMenu(
        settings: settings,
        state: state,
        model: model
      ) {
        onOpenSettings(.mapping)
      }
    }
  }

  private var preferenceSection: some View {
    SettingsSection(localization.text("status_panel.section.preferences")) {
      SettingsRow {
        Image(systemName: "power")
          .foregroundStyle(.secondary)
          .frame(width: 18)
        Toggle(
          localization.text("menu.launch_at_login"),
          isOn: $loginItem.isEnabled
        )
        .toggleStyle(.switch)
        .controlSize(.small)
      }

      if loginItem.state == .requiresApproval || isLoginItemFailure {
        SettingsDivider()
        StatusPanelActionButton(
          title: localization.text(
            isLoginItemFailure
              ? "menu.login_item.failed"
              : "menu.login_item.open_settings"
          ),
          systemImage: "exclamationmark.triangle",
          trailingSystemImage: "arrow.up.forward"
        ) {
          onOpenLoginItemSettings()
        }
      }

      SettingsDivider()
      SettingsRow {
        Image(systemName: "globe")
          .foregroundStyle(.secondary)
          .frame(width: 18)
        Text(localization.text("menu.language"))
        Spacer(minLength: 8)
        Picker("", selection: languageBinding) {
          ForEach(AppLanguage.allCases) { language in
            Text(languageTitle(language)).tag(language)
          }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 118)
      }
      SettingsDivider()
      StatusPanelActionButton(
        title: localization.text("menu.open_log_folder"),
        systemImage: "doc.text.magnifyingglass",
        trailingSystemImage: "arrow.up.forward"
      ) {
        model.openLogFolder()
      }
    }
  }

  private var finalActions: some View {
    VStack(spacing: 0) {
      StatusPanelActionButton(
        title: localization.text("menu.open_settings"),
        systemImage: "gearshape"
      ) {
        onOpenSettings(.connection)
      }

      SettingsDivider()
      StatusPanelActionButton(
        title: localization.text("common.action.quit"),
        systemImage: "power",
        action: onQuit
      )
    }
  }

  private var languageBinding: Binding<AppLanguage> {
    Binding(
      get: { settings.applicationLanguage },
      set: { localization.select($0) }
    )
  }

  private var isLoginItemFailure: Bool {
    if case .failed = loginItem.state { return true }
    return false
  }

  private func languageTitle(_ language: AppLanguage) -> String {
    language == .system
      ? localization.text("language.system")
      : language.nativeDisplayName
  }
}
