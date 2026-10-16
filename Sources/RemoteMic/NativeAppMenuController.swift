import AppKit

/// Supplies the standard commands previously installed by the SwiftUI app lifecycle.
@MainActor
final class NativeAppMenuController: NSObject {
  let menu = NSMenu()

  private let localization: LocalizationStore
  private let onOpenSettings: () -> Void
  private let onCloseSettings: () -> Void
  private let onQuit: () -> Void

  init(
    localization: LocalizationStore,
    onOpenSettings: @escaping () -> Void,
    onCloseSettings: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    self.localization = localization
    self.onOpenSettings = onOpenSettings
    self.onCloseSettings = onCloseSettings
    self.onQuit = onQuit
    super.init()
    rebuild()
  }

  func rebuild() {
    menu.removeAllItems()

    let appMenu = submenu(title: localization.text("app.name"))
    appMenu.addItem(
      command("menu.open_settings", action: #selector(openSettings(_:)), key: ",")
    )
    appMenu.addItem(.separator())
    appMenu.addItem(command("common.action.quit", action: #selector(quit(_:)), key: "q"))

    let fileMenu = submenu(title: localization.text("main_menu.file"))
    fileMenu.addItem(
      command("main_menu.close_window", action: #selector(closeSettings(_:)), key: "w")
    )

    let editMenu = submenu(title: localization.text("main_menu.edit"))
    editMenu.addItem(editCommand("undo", action: Selector(("undo:")), key: "z"))
    let redo = editCommand("redo", action: Selector(("redo:")), key: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(.separator())
    editMenu.addItem(editCommand("cut", action: #selector(NSText.cut(_:)), key: "x"))
    editMenu.addItem(editCommand("copy", action: #selector(NSText.copy(_:)), key: "c"))
    editMenu.addItem(editCommand("paste", action: #selector(NSText.paste(_:)), key: "v"))
    editMenu.addItem(editCommand("select_all", action: #selector(NSText.selectAll(_:)), key: "a"))
  }

  private func submenu(title: String) -> NSMenu {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    item.submenu = submenu
    menu.addItem(item)
    return submenu
  }

  private func command(_ titleKey: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(
      title: localization.text(titleKey), action: action, keyEquivalent: key
    )
    item.keyEquivalentModifierMask = [.command]
    item.target = self
    return item
  }

  private func editCommand(_ name: String, action: Selector, key: String) -> NSMenuItem {
    let item = command("main_menu.\(name)", action: action, key: key)
    // The focused text editor, rather than the app controller, handles text commands.
    item.target = nil
    return item
  }

  @objc private func openSettings(_ sender: NSMenuItem) { onOpenSettings() }
  @objc private func closeSettings(_ sender: NSMenuItem) { onCloseSettings() }
  @objc private func quit(_ sender: NSMenuItem) { onQuit() }
}
