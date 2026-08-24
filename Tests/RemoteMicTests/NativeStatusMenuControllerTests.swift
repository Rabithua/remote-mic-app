import ServiceManagement
import Testing

@testable import RemoteMic

@MainActor
@Suite("Native status menu", .serialized)
struct NativeStatusMenuControllerTests {
  @Test func exposesTheRequiredRootItemsAndSystemShortcuts() throws {
    let suiteName = "RemoteMicTests.NativeStatusMenu.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    let state = AppRuntimeState()
    let model = BridgeAppModel(settings: settings, state: state)
    let loginItem = LoginItemManager(service: NativeMenuLoginItemService())
    let localization = LocalizationStore(settings: settings)
    let controller = NativeStatusMenuController(
      settings: settings,
      state: state,
      model: model,
      loginItem: loginItem,
      localization: localization,
      onOpenSettings: { _ in },
      onLanguageChange: {},
      onQuit: {}
    )

    let entries = controller.menu.items.compactMap { item in
      item.identifier.flatMap { StatusMenuEntry(rawValue: $0.rawValue) }
    }
    #expect(entries == StatusMenuEntry.allCases)

    let quickMapping = try #require(
      controller.menu.items.first {
        $0.identifier?.rawValue == StatusMenuEntry.quickMapping.rawValue
      }
    )
    let language = try #require(
      controller.menu.items.first {
        $0.identifier?.rawValue == StatusMenuEntry.language.rawValue
      }
    )
    let settingsItem = try #require(
      controller.menu.items.first {
        $0.identifier?.rawValue == StatusMenuEntry.settings.rawValue
      }
    )
    let quitItem = try #require(
      controller.menu.items.first {
        $0.identifier?.rawValue == StatusMenuEntry.quit.rawValue
      }
    )

    #expect(quickMapping.submenu != nil)
    #expect(language.submenu != nil)
    #expect(settingsItem.keyEquivalent == ",")
    #expect(settingsItem.keyEquivalentModifierMask == [.command])
    #expect(quitItem.keyEquivalent == "q")
    #expect(quitItem.keyEquivalentModifierMask == [.command])
  }
}

@MainActor
private struct NativeMenuLoginItemService: LoginItemServicing {
  let status: SMAppService.Status = .notRegistered

  func register() throws {}
  func unregister() throws {}
}
