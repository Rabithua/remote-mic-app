import AppKit
import CoreBluetooth
import SwiftUI

struct PermissionSettingsView: View {
  let model: BridgeAppModel

  @EnvironmentObject private var localization: LocalizationStore
  @State private var bluetoothGranted = false
  @State private var inputMonitoringGranted = false
  @State private var accessibilityGranted = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SettingsPageHeader(
          title: localization.text("permissions.page.title"),
          subtitle: localization.text("permissions.page.subtitle.compact")
        )

        SettingsSection(localization.text("settings.section.permissions")) {
          PermissionRow(
            icon: "antenna.radiowaves.left.and.right",
            title: localization.text("permission.bluetooth.title"),
            description: localization.text("permission.bluetooth.description"),
            granted: bluetoothGranted,
            grantedText: localization.text("permission.status.enabled"),
            pendingText: localization.text("permission.status.pending"),
            actionTitle: localization.text("permission.action.open_settings"),
            action: model.requestBluetoothPermission
          )
          SettingsDivider()
          PermissionRow(
            icon: "eye",
            title: localization.text("permission.input_monitoring.title"),
            description: localization.text("permission.input_monitoring.description"),
            granted: inputMonitoringGranted,
            grantedText: localization.text("permission.status.enabled"),
            pendingText: localization.text("permission.status.pending"),
            actionTitle: localization.text("permission.action.open_settings"),
            action: model.requestInputMonitoringPermission
          )
          SettingsDivider()
          PermissionRow(
            icon: "hand.raised",
            title: localization.text("permission.accessibility.title"),
            description: localization.text("permission.accessibility.description"),
            granted: accessibilityGranted,
            grantedText: localization.text("permission.status.enabled"),
            pendingText: localization.text("permission.status.pending"),
            actionTitle: localization.text("permission.action.open_settings"),
            action: model.requestAccessibilityPermission
          )
        }

        Text(localization.text("permissions.restart_hint"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(SayAllDesign.contentPadding)
    }
    .onAppear(perform: refreshPermissions)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      refreshPermissions()
    }
  }

  private func refreshPermissions() {
    bluetoothGranted = CBManager.authorization == .allowedAlways
    inputMonitoringGranted = HIDRemoteMonitor.isInputMonitoringGranted
    accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
    model.refreshHIDAfterPermissionChange()
  }
}
