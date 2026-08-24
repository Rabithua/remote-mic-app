import AppKit
import SwiftUI

struct QuickMappingMenuPresenter: NSViewRepresentable {
  let accessibilityLabel: String
  let makeMenu: @MainActor () -> NSMenu

  func makeNSView(context: Context) -> QuickMappingMenuHostView {
    let view = QuickMappingMenuHostView()
    update(view)
    return view
  }

  func updateNSView(_ nsView: QuickMappingMenuHostView, context: Context) {
    update(nsView)
  }

  private func update(_ view: QuickMappingMenuHostView) {
    view.accessibilityTitle = accessibilityLabel
    view.makeMenu = makeMenu
  }
}

final class QuickMappingMenuHostView: NSView {
  var accessibilityTitle = "" {
    didSet { setAccessibilityLabel(accessibilityTitle) }
  }
  var makeMenu: (@MainActor () -> NSMenu)?

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.menuButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    // Opening on mouse-up prevents the release event from immediately dismissing NSMenu.
  }

  override func mouseUp(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    guard bounds.contains(location) else { return }
    presentMenu()
  }

  override func accessibilityPerformPress() -> Bool {
    presentMenu()
    return true
  }

  private func presentMenu() {
    guard let menu = makeMenu?() else { return }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: bounds.minX, y: bounds.maxY),
      in: self
    )
  }
}
