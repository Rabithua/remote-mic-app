import SwiftUI

struct ConnectionAudioSettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel

  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SettingsPageHeader(
          title: localization.text("connection.page.title.compact"),
          subtitle: localization.text("connection.page.subtitle.compact")
        )

        SettingsSection(localization.text("connection.remote.section_title")) {
          RuntimeStatusRow(
            icon: "antenna.radiowaves.left.and.right",
            title: localization.text("connection.status.bluetooth_title"),
            detail: state.connectionStatus.text(using: localization),
            healthy: state.isConnected
          )
          SettingsDivider()
          RuntimeStatusRow(
            icon: "waveform",
            title: localization.text("connection.status.voice_title"),
            detail: localization.text(
              state.isStreaming
                ? "connection.status.voice_streaming"
                : "connection.status.waiting_voice_button"
            ),
            healthy: state.isConnected
          )
          SettingsDivider()
          SettingsRow {
            Spacer(minLength: 0)
            Button {
              model.reconnect()
            } label: {
              Label(
                localization.text("connection.action.reconnect"),
                systemImage: "arrow.clockwise"
              )
              .padding(.horizontal, 8)
              .frame(minHeight: 28)
              .contentShape(Rectangle())
            }
            .controlSize(.small)
          }

          if settings.remoteDeviceProfiles.isEmpty {
            SettingsDivider()
            SettingsRow {
              Text(localization.text("connection.remote.none"))
                .foregroundStyle(.secondary)
            }
          } else {
            ForEach(settings.remoteDeviceProfiles) { profile in
              SettingsDivider()
              RemoteProfileRow(
                connected: model.isRemoteConnected(profile.id),
                selected: settings.selectedRemoteProfileID == profile.id,
                batteryLevel: model.batteryLevel(for: profile.id),
                displayName: profile.customName.isEmpty
                  ? localization.text(profile.displayNameFallbackKey)
                  : profile.customName,
                connectedText: localization.text("common.status.connected"),
                disconnectedText: localization.text("common.status.stopped")
              ) {
                model.selectRemoteProfile(profile.id)
              }
            }
          }
        }

        SettingsSection(localization.text("audio.section.title")) {
          SettingsRow {
            Label(localization.text("audio.output.title"), systemImage: "speaker.wave.2")
              .frame(width: 130, alignment: .leading)
            Picker("", selection: audioDeviceBinding) {
              Text(localization.text("audio.output.disabled")).tag("")
              ForEach(state.audioDevices) { device in
                Text(device.name).tag(device.uid)
              }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
          }
          SettingsDivider()
          SettingsRow {
            Label(localization.text("audio.gain.title"), systemImage: "dial.medium")
              .frame(width: 130, alignment: .leading)
            Slider(value: $settings.gainDB, in: -12...24, step: 1)
            Text("\(Int(settings.gainDB)) dB")
              .monospacedDigit()
              .frame(width: 54, alignment: .trailing)
          }
          SettingsDivider()
          RuntimeStatusRow(
            icon: "waveform.path.ecg",
            title: localization.text("audio.status.title"),
            detail: state.audioStatus.text(using: localization),
            healthy: state.isAudioOutputReady
          )
          SettingsDivider()
          SettingsRow {
            Button {
              model.refreshAudioDevices()
            } label: {
              Label(
                localization.text("audio.action.refresh_devices"),
                systemImage: "arrow.clockwise"
              )
              .padding(.horizontal, 8)
              .frame(minHeight: 28)
              .contentShape(Rectangle())
            }
            .controlSize(.small)

            Button {
              model.sendTestTone()
            } label: {
              Label(
                localization.text("audio.action.send_test_tone"),
                systemImage: "speaker.wave.2"
              )
              .padding(.horizontal, 8)
              .frame(minHeight: 28)
              .contentShape(Rectangle())
            }
            .controlSize(.small)
            .disabled(!model.canSendTestTone)

            Spacer(minLength: 8)
            Text(state.testToneStatus.text(using: localization))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
      .padding(SayAllDesign.contentPadding)
    }
  }

  private var audioDeviceBinding: Binding<String> {
    Binding(
      get: { settings.selectedAudioDeviceUID },
      set: { value in
        settings.selectedAudioDeviceUID = value
        model.applyAudioSettings()
      }
    )
  }
}
