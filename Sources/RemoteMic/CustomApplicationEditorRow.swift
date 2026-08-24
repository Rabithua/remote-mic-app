import AppKit
import SwiftUI

struct CustomApplicationEditorRow: View {
  let profile: CustomApplicationProfile
  @Bindable var settings: AppSettings

  @EnvironmentObject private var localization: LocalizationStore
  @State private var showsFocusShortcutPicker = false
  @State private var accessibilityCaptureState: AccessibilityCaptureState = .idle

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
      GridRow {
        fieldLabel("custom_application.name")
        TextField("", text: profileBinding(\.displayName))
        Button(role: .destructive) {
          settings.removeCustomApplicationProfile(profile.id)
        } label: {
          Image(systemName: "trash")
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localization.text("custom_application.remove"))
      }

      GridRow {
        fieldLabel("custom_application.bundle_identifier")
        TextField("", text: profileBinding(\.bundleIdentifier))
          .textFieldStyle(.roundedBorder)
        trailingPlaceholder
      }

      GridRow {
        fieldLabel("custom_application.focus.title")
        Picker("", selection: profileBinding(\.focusStrategy)) {
          ForEach(CustomApplicationFocusStrategy.allCases) { strategy in
            Text(strategy.displayName(using: localization)).tag(strategy)
          }
        }
        .labelsHidden()
        trailingPlaceholder
      }

      if profile.focusStrategy == .keyboardShortcut {
        GridRow {
          fieldLabel("custom_application.focus.shortcut_edit")
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
                .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              localization.text("custom_application.focus.shortcut_edit")
            )
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
          trailingPlaceholder
        }
      }

      if profile.focusStrategy == .recordedAccessibility {
        GridRow {
          fieldLabel("custom_application.focus.record")
          VStack(alignment: .leading, spacing: 5) {
            Button {
              recordFocusedInput()
            } label: {
              Label(
                localization.text("custom_application.focus.record"),
                systemImage: "scope"
              )
              .padding(.horizontal, 8)
              .frame(minHeight: 28)
              .contentShape(Rectangle())
            }
            .controlSize(.small)
            .disabled(accessibilityCaptureState == .recording)

            Text(accessibilityStatus)
              .font(.caption)
              .foregroundStyle(accessibilityCaptureState.color)
          }
          trailingPlaceholder
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
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .controlSize(.small)
        trailingPlaceholder
      }
    }
  }

  private var trailingPlaceholder: some View {
    Color.clear.frame(width: 28, height: 1)
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

  private func fieldLabel(_ key: String) -> some View {
    Text(localization.text(key))
      .font(.callout)
      .foregroundStyle(.secondary)
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

  private func profileBinding<Value>(
    _ keyPath: WritableKeyPath<CustomApplicationProfile, Value>
  ) -> Binding<Value> {
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
