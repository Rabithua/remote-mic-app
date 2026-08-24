import Foundation

enum StatusItemClickPolicy {
  static func opensPanel(isRightClick _: Bool) -> Bool { true }
}

@MainActor
struct QuickMappingActionSelection: Equatable {
  let button: RemoteButton
  let action: ButtonAction

  func apply(to settings: AppSettings) {
    settings.setAction(action, for: button, trigger: .singleClick)
  }
}

struct QuickMappingActionGroup: Equatable {
  let category: ButtonActionCategory
  let actions: [ButtonAction]
}

@MainActor
enum ButtonMappingPresentation {
  static func actionSummary(
    configured: ConfiguredButtonAction,
    customApplicationName: String?,
    using localization: LocalizationStore
  ) -> String {
    guard configured.action != .disabled else {
      return localization.text("button_mapping.action.not_set")
    }
    if configured.action == .customShortcut, let shortcut = configured.shortcut {
      return shortcut.displayName(using: localization)
    }
    if configured.action == .openCustomApplication {
      return customApplicationName
        ?? localization.text("custom_application.not_configured")
    }
    switch configured.action {
    case .arrowUp: return "↑"
    case .arrowDown: return "↓"
    case .arrowLeft: return "←"
    case .arrowRight: return "→"
    case .deleteBackward: return "⌫"
    case .volumeUp: return "+"
    case .volumeDown: return "−"
    case .volumeMute: return "Mute"
    default: return configured.action.displayName(using: localization)
    }
  }

  static func remoteDisplayName(
    _ profile: RemoteDeviceProfile,
    among profiles: [RemoteDeviceProfile],
    using localization: LocalizationStore
  ) -> String {
    let base = localization.text(profile.displayNameFallbackKey)
    let peers = profiles.filter { $0.model == profile.model }
    guard peers.count > 1,
      let index = peers.firstIndex(where: { $0.id == profile.id })
    else { return base }
    return "\(base) \(index + 1)"
  }

  static func actionGroups(
    installedBundleIdentifiers: Set<String>,
    currentAction: ButtonAction,
    hasConfiguredShortcut: Bool,
    hasConfiguredApplication: Bool
  ) -> [QuickMappingActionGroup] {
    let actions = ButtonAction.pickerActions(
      installedBundleIdentifiers: installedBundleIdentifiers,
      current: currentAction
    ).filter { action in
      guard action != .disabled else { return false }
      if action == .customShortcut {
        return hasConfiguredShortcut || currentAction == action
      }
      if action == .openCustomApplication {
        return hasConfiguredApplication || currentAction == action
      }
      return true
    }

    return ButtonActionCategory.allCases.compactMap { category in
      let groupedActions = actions.filter { $0.category == category }
      return groupedActions.isEmpty
        ? nil
        : QuickMappingActionGroup(category: category, actions: groupedActions)
    }
  }
}
