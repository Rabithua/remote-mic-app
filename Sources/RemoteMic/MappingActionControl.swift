import AppKit
import SwiftUI

struct MappingActionControl: View {
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
    HStack(spacing: 4) {
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
                  Label(action.displayName(using: localization), systemImage: "checkmark")
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
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
        .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
      }
      .menuStyle(.borderlessButton)

      if configured.action == .customShortcut {
        Button {
          showsShortcutPicker.toggle()
        } label: {
          Image(systemName: "keyboard.badge.ellipsis")
            .frame(width: 28, height: 30)
            .contentShape(Rectangle())
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localization.text("custom_application.focus.shortcut_edit"))
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
              settings.setApplicationProfileID(profile.id, for: button, trigger: trigger)
              onChange()
            }
          }
          Divider()
          Button(localization.text("custom_application.choose")) {
            chooseApplication()
          }
        } label: {
          Image(systemName: "app.badge")
            .frame(width: 28, height: 30)
            .contentShape(Rectangle())
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(localization.text("custom_application.choose"))
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
