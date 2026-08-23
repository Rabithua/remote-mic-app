import AppKit
import CoreBluetooth
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
  case connection
  case mapping
  case permissions

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .connection: return "settings.section.connection_audio"
    case .mapping: return "settings.section.buttons"
    case .permissions: return "settings.section.permissions"
    }
  }

  var systemImage: String {
    switch self {
    case .connection: return "dot.radiowaves.left.and.right"
    case .mapping: return "keyboard"
    case .permissions: return "lock.shield"
    }
  }
}

struct SettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel
  @Bindable var navigation: SettingsNavigationModel

  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        List(SettingsPage.allCases, selection: $navigation.selection) { page in
          Label(localization.text(page.titleKey), systemImage: page.systemImage)
            .tag(page)
        }
        .listStyle(.sidebar)

        Divider()
        Button {
          settings.completeSetup()
          NSApp.keyWindow?.close()
        } label: {
          Text(localization.text("setup.action.done"))
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .padding(12)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 194, max: 220)
    } detail: {
      switch navigation.selection {
      case .connection:
        ConnectionAudioSettingsView(settings: settings, state: state, model: model)
      case .mapping:
        ButtonMappingSettingsView(settings: settings, state: state, model: model)
      case .permissions:
        PermissionSettingsView(model: model)
      }
    }
    .frame(minWidth: 760, minHeight: 540)
  }
}

private struct SettingsPageHeader: View {
  let titleKey: String
  let subtitleKey: String
  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(localization.text(titleKey))
        .font(.system(size: 24, weight: .bold))
      Text(localization.text(subtitleKey))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SettingsCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(.separator.opacity(0.45))
      }
  }
}

private struct ConnectionAudioSettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel

  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          titleKey: "connection.page.title.compact",
          subtitleKey: "connection.page.subtitle.compact"
        )

        SettingsCard {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Label(
                localization.text("connection.remote.section_title"),
                systemImage: "dot.radiowaves.left.and.right"
              )
              .font(.headline)
              Spacer()
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
            }

            statusLine(
              title: localization.text("connection.status.bluetooth_title"),
              value: state.connectionStatus.text(using: localization),
              healthy: state.isConnected
            )
            statusLine(
              title: localization.text("connection.status.voice_title"),
              value: localization.text(
                state.isStreaming
                  ? "connection.status.voice_streaming"
                  : "connection.status.waiting_voice_button"
              ),
              healthy: state.isConnected
            )

            if settings.remoteDeviceProfiles.isEmpty {
              Text(localization.text("connection.remote.none"))
                .foregroundStyle(.secondary)
            } else {
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 8)],
                alignment: .leading,
                spacing: 8
              ) {
                ForEach(settings.remoteDeviceProfiles) { profile in
                  remoteCard(profile)
                }
              }
            }
          }
        }

        SettingsCard {
          VStack(alignment: .leading, spacing: 14) {
            Text(localization.text("audio.section.title"))
              .font(.headline)

            Picker(
              localization.text("audio.output.title"),
              selection: Binding(
                get: { settings.selectedAudioDeviceUID },
                set: { value in
                  settings.selectedAudioDeviceUID = value
                  model.applyAudioSettings()
                }
              )
            ) {
              Text(localization.text("audio.output.disabled")).tag("")
              ForEach(state.audioDevices) { device in
                Text(device.name).tag(device.uid)
              }
            }

            HStack(spacing: 12) {
              Text(localization.text("audio.gain.title"))
                .frame(width: 72, alignment: .leading)
              Slider(value: $settings.gainDB, in: -12...24, step: 1)
              Text("\(Int(settings.gainDB)) dB")
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            }

            Text(state.audioStatus.text(using: localization))
              .font(.callout)
              .foregroundStyle(state.isAudioOutputReady ? Color.secondary : Color.orange)

            HStack {
              Button {
                model.refreshAudioDevices()
              } label: {
                Label(
                  localization.text("audio.action.refresh_devices"),
                  systemImage: "arrow.clockwise"
                )
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
              }
              Button {
                model.sendTestTone()
              } label: {
                Label(
                  localization.text("audio.action.send_test_tone"),
                  systemImage: "speaker.wave.2"
                )
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
              }
              .disabled(!model.canSendTestTone)
              Spacer()
              Text(state.testToneStatus.text(using: localization))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(24)
    }
  }

  @ViewBuilder
  private func remoteCard(_ profile: RemoteDeviceProfile) -> some View {
    let connected = model.isRemoteConnected(profile.id)
    Button {
      model.selectRemoteProfile(profile.id)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: connected ? "remote.fill" : "remote")
          .foregroundStyle(connected ? Color.accentColor : Color.secondary)
        VStack(alignment: .leading, spacing: 3) {
          Text(
            profile.customName.isEmpty
              ? localization.text(profile.displayNameFallbackKey)
              : profile.customName
          )
          .fontWeight(.semibold)
          HStack(spacing: 6) {
            Text(
              connected
                ? localization.text("common.status.connected")
                : localization.text("common.status.stopped"))
            if let level = model.batteryLevel(for: profile.id) {
              Text("· \(level)%")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if settings.selectedRemoteProfileID == profile.id {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color.accentColor)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
      .contentShape(Rectangle())
      .background(.background, in: RoundedRectangle(cornerRadius: 9))
      .overlay {
        RoundedRectangle(cornerRadius: 9)
          .stroke(
            settings.selectedRemoteProfileID == profile.id
              ? Color.accentColor.opacity(0.65)
              : Color.secondary.opacity(0.18)
          )
      }
    }
    .buttonStyle(.plain)
  }

  private func statusLine(title: String, value: String, healthy: Bool) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Circle()
        .fill(healthy ? Color.green : Color.orange)
        .frame(width: 8, height: 8)
      Text(title)
        .fontWeight(.medium)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }
}

private struct ButtonMappingSettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var state: AppRuntimeState
  let model: BridgeAppModel

  @EnvironmentObject private var localization: LocalizationStore

  private let gridColumns: [GridItem] = [
    GridItem(.fixed(92), spacing: 8, alignment: .leading),
    GridItem(.flexible(minimum: 120), spacing: 8),
    GridItem(.flexible(minimum: 120), spacing: 8),
    GridItem(.flexible(minimum: 120), spacing: 8),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          titleKey: "button_mapping.page.title",
          subtitleKey: "button_mapping.page.subtitle.compact"
        )

        SettingsCard {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
              Toggle(
                localization.text("button_mapping.toggle.enabled"),
                isOn: Binding(
                  get: { settings.customMappingEnabled },
                  set: { value in
                    settings.customMappingEnabled = value
                    model.applyHIDSettings()
                  }
                )
              )
              Spacer()
              if !settings.remoteDeviceProfiles.isEmpty {
                Picker(
                  localization.text("menu.button_mapping.remote"),
                  selection: Binding(
                    get: { settings.selectedRemoteProfileID },
                    set: { id in if let id { model.selectRemoteProfile(id) } }
                  )
                ) {
                  ForEach(settings.remoteDeviceProfiles) { profile in
                    Text(
                      profile.customName.isEmpty
                        ? localization.text(profile.displayNameFallbackKey)
                        : profile.customName
                    )
                    .tag(Optional(profile.id))
                  }
                }
                .frame(maxWidth: 250)
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
            }

            Divider()
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
              Text(localization.text("button_mapping.grid.button"))
              ForEach(ButtonTrigger.allCases) { trigger in
                Text(trigger.displayName(using: localization))
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
              }

              ForEach(RemoteButton.allCases) { button in
                Text(button.displayName(using: localization))
                  .fontWeight(
                    state.lastRemoteButtonPress == button ? .bold : .regular
                  )
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
          }
        }

        if !settings.customApplicationProfiles.isEmpty {
          SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
              Text(localization.text("custom_application.saved.title"))
                .font(.headline)
              ForEach(settings.customApplicationProfiles) { profile in
                CustomApplicationEditorRow(profile: profile, settings: settings)
                if profile.id != settings.customApplicationProfiles.last?.id {
                  Divider()
                }
              }
            }
          }
        }
      }
      .padding(24)
    }
  }
}

private struct MappingActionControl: View {
  let button: RemoteButton
  let trigger: ButtonTrigger
  @Bindable var settings: AppSettings
  let onChange: () -> Void

  @EnvironmentObject private var localization: LocalizationStore
  @State private var showsShortcutPicker = false

  private var configured: ConfiguredButtonAction {
    settings.configuredAction(for: button, trigger: trigger)
  }

  var body: some View {
    HStack(spacing: 5) {
      Menu {
        ForEach(ButtonActionCategory.allCases) { category in
          let actions = ButtonAction.allCases.filter { $0.category == category }
          Menu(localization.text(category.localizationKey)) {
            ForEach(actions) { action in
              Button {
                settings.setAction(action, for: button, trigger: trigger)
                if action == .customShortcut, configured.shortcut == nil {
                  showsShortcutPicker = true
                }
                onChange()
              } label: {
                if configured.action == action {
                  Label(
                    action.displayName(using: localization),
                    systemImage: "checkmark"
                  )
                } else {
                  Text(action.displayName(using: localization))
                }
              }
            }
          }
        }
      } label: {
        HStack(spacing: 5) {
          Text(actionSummary)
            .lineLimit(1)
          Spacer(minLength: 0)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(Rectangle())
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.secondary.opacity(0.22))
        }
      }
      .menuStyle(.borderlessButton)

      if configured.action == .customShortcut {
        Button {
          showsShortcutPicker.toggle()
        } label: {
          Image(systemName: "keyboard.badge.ellipsis")
            .frame(width: 28, height: 32)
            .contentShape(Rectangle())
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsShortcutPicker) {
          ScrollView {
            KeyboardShortcutPicker(shortcut: configured.shortcut) { shortcut in
              settings.setShortcut(shortcut, for: button, trigger: trigger)
              showsShortcutPicker = false
              onChange()
            }
            .padding(16)
          }
          .frame(width: 680, height: 500)
        }
      } else if configured.action == .openCustomApplication {
        Menu {
          ForEach(settings.customApplicationProfiles) { profile in
            Button(profile.displayName) {
              settings.setApplicationProfileID(
                profile.id,
                for: button,
                trigger: trigger
              )
              onChange()
            }
          }
          Divider()
          Button(localization.text("custom_application.choose")) {
            chooseApplication()
          }
        } label: {
          Image(systemName: "app.badge")
            .frame(width: 28, height: 32)
            .contentShape(Rectangle())
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
      }
    }
  }

  private var actionSummary: String {
    ButtonMappingPresentation.actionSummary(
      configured: configured,
      customApplicationName: settings.customApplicationProfile(
        id: configured.applicationProfileID
      )?.displayName,
      using: localization
    )
  }

  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let bundle = Bundle(url: url)
    let profile = CustomApplicationProfile(
      displayName: FileManager.default.displayName(atPath: url.path),
      bundleIdentifier: bundle?.bundleIdentifier ?? "",
      applicationPath: url.path
    )
    let id = settings.addCustomApplicationProfile(profile)
    settings.setApplicationProfileID(id, for: button, trigger: trigger)
    onChange()
  }
}

private struct CustomApplicationEditorRow: View {
  let profile: CustomApplicationProfile
  @Bindable var settings: AppSettings
  @EnvironmentObject private var localization: LocalizationStore
  @State private var showsFocusShortcutPicker = false
  @State private var accessibilityCaptureState: AccessibilityCaptureState = .idle

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
      GridRow {
        Text(localization.text("custom_application.name"))
          .foregroundStyle(.secondary)
        TextField("", text: profileBinding(\.displayName))
        Button(role: .destructive) {
          settings.removeCustomApplicationProfile(profile.id)
        } label: {
          Image(systemName: "trash")
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      GridRow {
        Text(localization.text("custom_application.bundle_identifier"))
          .foregroundStyle(.secondary)
        TextField("", text: profileBinding(\.bundleIdentifier))
          .textFieldStyle(.roundedBorder)
        Color.clear.frame(width: 28, height: 1)
      }
      GridRow {
        Text(localization.text("custom_application.focus.title"))
          .foregroundStyle(.secondary)
        Picker("", selection: profileBinding(\.focusStrategy)) {
          ForEach(CustomApplicationFocusStrategy.allCases) { strategy in
            Text(strategy.displayName(using: localization)).tag(strategy)
          }
        }
        .labelsHidden()
        Color.clear.frame(width: 28, height: 1)
      }
      if profile.focusStrategy == .keyboardShortcut {
        GridRow {
          Text(localization.text("custom_application.focus.shortcut_edit"))
            .foregroundStyle(.secondary)
          HStack {
            Text(
              profile.focusShortcut?.displayName(using: localization)
                ?? localization.text("button_mapping.action.not_set")
            )
            .foregroundStyle(profile.focusShortcut == nil ? .secondary : .primary)
            Spacer()
            Button {
              showsFocusShortcutPicker.toggle()
            } label: {
              Image(systemName: "keyboard.badge.ellipsis")
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsFocusShortcutPicker) {
              ScrollView {
                KeyboardShortcutPicker(shortcut: profile.focusShortcut) { shortcut in
                  var updated = profile
                  updated.focusShortcut = shortcut
                  settings.updateCustomApplicationProfile(updated)
                  showsFocusShortcutPicker = false
                }
                .padding(16)
              }
              .frame(width: 680, height: 500)
            }
          }
          Color.clear.frame(width: 28, height: 1)
        }
      }
      if profile.focusStrategy == .recordedAccessibility {
        GridRow {
          Text(localization.text("custom_application.focus.record"))
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 5) {
            Button {
              recordFocusedInput()
            } label: {
              Label(
                localization.text("custom_application.focus.record"),
                systemImage: "scope"
              )
              .padding(.horizontal, 8)
              .frame(minHeight: 30)
              .contentShape(Rectangle())
            }
            .disabled(accessibilityCaptureState == .recording)
            Text(accessibilityStatus)
              .font(.caption)
              .foregroundStyle(accessibilityCaptureState.color)
          }
          Color.clear.frame(width: 28, height: 1)
        }
      }
      GridRow {
        Color.clear.frame(width: 1, height: 1)
        Button {
          _ = KeyboardInjector.send(
            .openCustomApplication,
            applicationProfile: profile
          )
        } label: {
          Text(localization.text("custom_application.focus.test"))
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        Color.clear.frame(width: 28, height: 1)
      }
    }
  }

  private var accessibilityStatus: String {
    switch accessibilityCaptureState {
    case .idle:
      return localization.text(
        profile.accessibilityTarget == nil
          ? "custom_application.focus.not_recorded_status"
          : "custom_application.focus.recorded_status"
      )
    case .recording:
      return localization.text("custom_application.focus.capture_wait")
    case .failed:
      return localization.text("custom_application.focus.capture_failed")
    case .succeeded:
      return localization.text("custom_application.focus.recorded_status")
    }
  }

  private func recordFocusedInput() {
    guard KeyboardInjector.isAccessibilityTrusted else {
      _ = KeyboardInjector.requestAccessibilityAccess()
      accessibilityCaptureState = .failed
      return
    }
    let savedURL = URL(fileURLWithPath: profile.applicationPath)
    let applicationURL =
      Bundle(url: savedURL)?.bundleIdentifier == profile.bundleIdentifier
      ? savedURL
      : NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: profile.bundleIdentifier
      )
    guard let applicationURL else {
      accessibilityCaptureState = .failed
      return
    }

    accessibilityCaptureState = .recording
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = false
    let profileID = profile.id
    let bundleIdentifier = profile.bundleIdentifier
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: configuration
    ) { _, error in
      Task { @MainActor in
        guard error == nil else {
          accessibilityCaptureState = .failed
          return
        }
        try? await Task.sleep(for: .seconds(3))
        guard
          let target = KeyboardInjector.captureFocusedAccessibilityTarget(
            bundleIdentifier: bundleIdentifier
          ),
          var updated = settings.customApplicationProfile(id: profileID)
        else {
          accessibilityCaptureState = .failed
          NSApp.activate(ignoringOtherApps: true)
          return
        }
        updated.accessibilityTarget = target
        updated.focusStrategy = .recordedAccessibility
        settings.updateCustomApplicationProfile(updated)
        accessibilityCaptureState = .succeeded
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }

  private func profileBinding<Value>(_ keyPath: WritableKeyPath<CustomApplicationProfile, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { profile[keyPath: keyPath] },
      set: { value in
        var updated = profile
        updated[keyPath: keyPath] = value
        settings.updateCustomApplicationProfile(updated)
      }
    )
  }
}

private enum AccessibilityCaptureState: Equatable {
  case idle
  case recording
  case failed
  case succeeded

  var color: Color {
    switch self {
    case .idle: return .secondary
    case .recording: return .orange
    case .failed: return .red
    case .succeeded: return .green
    }
  }
}

private struct PermissionSettingsView: View {
  let model: BridgeAppModel
  @EnvironmentObject private var localization: LocalizationStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          titleKey: "permissions.page.title",
          subtitleKey: "permissions.page.subtitle.compact"
        )

        SettingsCard {
          VStack(spacing: 0) {
            permissionRow(
              icon: "antenna.radiowaves.left.and.right",
              titleKey: "permission.bluetooth.title",
              descriptionKey: "permission.bluetooth.description",
              granted: model.bluetoothPermissionGranted,
              action: model.requestBluetoothPermission
            )
            Divider().padding(.vertical, 10)
            permissionRow(
              icon: "eye",
              titleKey: "permission.input_monitoring.title",
              descriptionKey: "permission.input_monitoring.description",
              granted: HIDRemoteMonitor.isInputMonitoringGranted,
              action: model.requestInputMonitoringPermission
            )
            Divider().padding(.vertical, 10)
            permissionRow(
              icon: "hand.raised",
              titleKey: "permission.accessibility.title",
              descriptionKey: "permission.accessibility.description",
              granted: KeyboardInjector.isAccessibilityTrusted,
              action: model.requestAccessibilityPermission
            )
          }
        }

        Text(localization.text("permissions.restart_hint"))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .padding(24)
    }
    .onAppear {
      model.refreshHIDAfterPermissionChange()
    }
  }

  private func permissionRow(
    icon: String,
    titleKey: String,
    descriptionKey: String,
    granted: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 20))
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(localization.text(titleKey))
          .fontWeight(.semibold)
        Text(localization.text(descriptionKey))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Label(
        localization.text(granted ? "permission.status.enabled" : "permission.status.pending"),
        systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
      )
      .foregroundStyle(granted ? Color.green : Color.orange)
      Button(action: action) {
        Text(localization.text("permission.action.open_settings"))
          .padding(.horizontal, 8)
          .frame(minHeight: 30)
          .contentShape(Rectangle())
      }
    }
  }
}
