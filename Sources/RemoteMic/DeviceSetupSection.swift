import AppKit
import SwiftUI

struct DeviceSetupSection: View {
  let state: AppRuntimeState
  let model: BridgeAppModel
  @EnvironmentObject private var localization: LocalizationStore
  @State private var diagnosticsCopied = false

  var body: some View {
    SettingsSection(localization.text("device_setup.title")) {
      SettingsRow {
        Label(
          localization.text("permission.bluetooth.title"),
          systemImage: state.bluetoothPermissionGranted
            ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
        )
        Spacer(minLength: 0)
        if state.bluetoothPermissionGranted {
          Text(localization.text("permission.status.enabled"))
            .foregroundStyle(.secondary)
        } else {
          Button(
            localization.text("device_setup.bluetooth.allow"),
            action: model.requestBluetoothPermission
          )
          .buttonStyle(.borderedProminent)
        }
      }
      SettingsDivider()
      SettingsRow {
        VStack(alignment: .leading, spacing: 6) {
          Text(localization.text("device_setup.remote.title"))
          if !state.isConnected {
            Text(localization.text("device_setup.remote.pairing_hint"))
              .font(.caption)
              .foregroundStyle(.secondary)
            if let issue = state.lastConnectionIssue {
              Text(issue.text(using: localization))
                .font(.caption)
                .foregroundStyle(.orange)
            }
          } else {
            Text(state.connectionStatus.text(using: localization))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack {
            Button(
              localization.text("device_setup.remote.pair"), action: model.openBluetoothPairing
            )
            .buttonStyle(.bordered)
            if !state.isConnected {
              Button(localization.text("device_setup.remote.scan"), action: model.reconnect)
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
          }
        }
      }
      SettingsDivider()
      SettingsRow {
        VStack(alignment: .leading, spacing: 4) {
          Text(localization.text("device_setup.driver.title"))
          Text(localization.text(model.audioDriver.status.messageKey))
            .font(.caption)
            .foregroundStyle(.secondary)
          if let message = model.audioDriver.message {
            Text(message.text(using: localization))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if model.audioDriver.status == .ready, !model.hasDoubaoAudioDevice {
            Text(localization.text("device_setup.driver.waiting_for_device"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
        if model.audioDriver.isInstalling {
          ProgressView().controlSize(.small)
            .accessibilityLabel(localization.text("device_setup.driver.installing"))
        } else if model.audioDriver.status.canInstall {
          Button(localization.text("device_setup.driver.install"), action: installDriver)
            .buttonStyle(.borderedProminent)
            .disabled(state.isStreaming || state.isPlayingTestTone)
        } else if model.hasDoubaoAudioDevice {
          Button(
            localization.text("device_setup.driver.select"), action: model.selectDoubaoAudioDevice
          )
          .buttonStyle(.bordered)
        }
      }
      if !state.inputMonitoringGranted || !state.accessibilityGranted {
        SettingsDivider()
        SettingsRow {
          VStack(alignment: .leading, spacing: 6) {
            Text(localization.text("device_setup.buttons.title"))
            HStack {
              if !state.inputMonitoringGranted {
                Button(
                  localization.text("permission.input_monitoring.title"),
                  action: model.requestInputMonitoringPermission
                )
                .buttonStyle(.bordered)
              }
              if !state.accessibilityGranted {
                Button(
                  localization.text("permission.accessibility.title"),
                  action: model.requestAccessibilityPermission
                )
                .buttonStyle(.bordered)
              }
            }
          }
        }
      }
      SettingsDivider()
      SettingsRow {
        Button(
          localization.text(
            diagnosticsCopied ? "device_setup.diagnostics.copied" : "device_setup.diagnostics.copy"),
          action: copyDiagnostics
        )
        .buttonStyle(.bordered)
        Spacer(minLength: 0)
        Button(localization.text("device_setup.refresh"), action: refresh)
          .buttonStyle(.bordered)
      }
    }
    .controlSize(.small)
    .task { await model.refreshDeviceSetup() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      refresh()
    }
  }

  private func installDriver() {
    Task { await model.installVirtualMicrophone() }
  }

  private func refresh() {
    Task { await model.refreshDeviceSetup() }
  }

  private func copyDiagnostics() {
    Task {
      await model.copyConnectionDiagnostics(using: localization)
      diagnosticsCopied = true
    }
  }
}
