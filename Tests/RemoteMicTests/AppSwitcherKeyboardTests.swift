import CoreGraphics
import Testing

@testable import RemoteMic

struct AppSwitcherKeyboardTests {
  @Test func cancellationHoldsEscapeBeforeReleasingCommand() {
    var events: [String] = []
    let post = KeyboardInjector.makeAppSwitcherKeyPoster(
      postEvent: { event in
        events.append("\(event.getIntegerValueField(.keyboardEventKeycode)):\(event.type.rawValue)")
      },
      holdEscape: { events.append("holdEscape") })
    #expect(post(55, true, .maskCommand))
    #expect(post(53, true, .maskCommand))
    #expect(post(53, false, .maskCommand))
    #expect(post(55, false, []))
    #expect(events == ["55:12", "53:10", "holdEscape", "53:11", "55:12"])
  }

  @Test func ordinarySwitcherKeysDoNotWaitForEscape() {
    var holds = 0
    let post = KeyboardInjector.makeAppSwitcherKeyPoster(
      postEvent: { _ in }, holdEscape: { holds += 1 })
    #expect(KeyboardInjector.postAppSwitcherTap(keyStatePoster: post))
    #expect(holds == 0)
  }

  @Test func aQuickSwitchExplicitlyPressesAndReleasesCommand() {
    var events: [String] = []
    #expect(
      KeyboardInjector.postAppSwitcherTap(keyStatePoster: { code, down, _ in
        events.append("\(code):\(down)")
        return true
      }))
    #expect(events == ["55:true", "48:true", "48:false", "55:false"])
  }

  @Test(arguments: [0, 1, 2, 3])
  func aQuickSwitchStillReleasesCommandAfterAnyPostingFailure(_ failedIndex: Int) {
    var events: [String] = []
    #expect(
      KeyboardInjector.postAppSwitcherTap(keyStatePoster: { code, down, _ in
        let index = events.count
        events.append("\(code):\(down)")
        return index != failedIndex
      }) == false)
    #expect(events.last == "55:false")
    if failedIndex != 0 { #expect(events.contains("48:false")) }
  }

  @Test func commandPreservesNativeModifierDeviceBitsAndReleaseFlags() throws {
    let source = try #require(CGEventSource(stateID: .privateState))
    let natural = try #require(CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true))
    let down = try #require(
      KeyboardInjector.makeAppSwitcherKeyboardEvent(
        source: source, code: 55, isDown: true, flags: .maskCommand))
    #expect(down.type == .flagsChanged)
    #expect(down.flags == natural.flags)
    #expect(down.flags.contains(.maskCommand))
    // NX_DEVICELCMDKEYMASK from Apple's IOLLEvent.h.
    #expect(down.flags.rawValue & 0x8 == 0x8)
    let up = try #require(
      KeyboardInjector.makeAppSwitcherKeyboardEvent(
        source: source, code: 55, isDown: false, flags: []))
    #expect(up.type == .flagsChanged)
    #expect(up.flags.contains(.maskCommand) == false)
    #expect(up.flags.rawValue & 0x8 == 0)
  }

  @Test func tabUsesTheSamePrivateSourceAndBypassesOurOwnSuppressor() throws {
    let source = try #require(CGEventSource(stateID: .privateState))
    for down in [true, false] {
      let event = try #require(
        KeyboardInjector.makeAppSwitcherKeyboardEvent(
          source: source, code: 48, isDown: down, flags: .maskCommand))
      #expect(event.type == (down ? .keyDown : .keyUp))
      #expect(event.flags.contains(.maskCommand))
      #expect(event.getIntegerValueField(.eventSourceStateID) == source.sourceStateID.rawValue)
      #expect(
        event.getIntegerValueField(.eventSourceUserData) == KeyboardInjector.syntheticEventMarker)
      #expect(KeyboardEventSuppressor().handle(type: event.type, event: event) == false)
    }
  }
}
