import AppKit
import Testing

@testable import RemoteMic

@MainActor
struct NativeAppMenuControllerTests {
  @Test func routesWindowShortcutsAndPreservesTextEditingCommands() throws {
    let suiteName = "RemoteMicTests.NativeAppMenu.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let localization = LocalizationStore(settings: AppSettings(defaults: defaults))
    var opened = 0
    var closed = 0
    let controller = NativeAppMenuController(
      localization: localization,
      onOpenSettings: { opened += 1 },
      onCloseSettings: { closed += 1 },
      onQuit: {}
    )
    let appMenu = try #require(controller.menu.item(at: 0)?.submenu)
    let fileMenu = try #require(controller.menu.item(at: 1)?.submenu)
    let editMenu = try #require(controller.menu.item(at: 2)?.submenu)
    let settingsItem = try #require(appMenu.items.first { $0.keyEquivalent == "," })
    let closeItem = try #require(fileMenu.items.first { $0.keyEquivalent == "w" })

    #expect(settingsItem.target === controller)
    #expect(closeItem.target === controller)
    _ = controller.perform(settingsItem.action, with: settingsItem)
    _ = controller.perform(closeItem.action, with: closeItem)
    #expect(opened == 1)
    #expect(closed == 1)

    let commands = editMenu.items.filter { $0.isSeparatorItem == false }
    #expect(commands.map(\.keyEquivalent) == ["z", "z", "x", "c", "v", "a"])
    #expect(
      commands.map { $0.action.map(NSStringFromSelector) } == [
        "undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:",
      ])
    #expect(commands.allSatisfy { $0.target == nil })
    #expect(commands[1].keyEquivalentModifierMask == [.command, .shift])
  }
}
