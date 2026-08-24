import AppKit

@MainActor
final class StatusPopoverDismissMonitor {
  private weak var popover: NSPopover?
  private weak var statusButton: NSStatusBarButton?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var onDismiss: (() -> Void)?

  func start(
    popover: NSPopover,
    statusButton: NSStatusBarButton,
    onDismiss: @escaping () -> Void
  ) {
    stop()
    self.popover = popover
    self.statusButton = statusButton
    self.onDismiss = onDismiss

    localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      let point = NSEvent.mouseLocation
      Task { @MainActor [weak self] in
        self?.handleClick(at: point)
      }
      return event
    }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      let point = NSEvent.mouseLocation
      Task { @MainActor [weak self] in
        self?.handleClick(at: point)
      }
    }
  }

  func stop() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    popover = nil
    statusButton = nil
    onDismiss = nil
  }

  private func handleClick(at point: NSPoint) {
    guard let popover, popover.isShown else {
      stop()
      return
    }
    let popoverFrame = popover.contentViewController?.view.window?.frame
    let statusButtonFrame = statusButton.flatMap { button -> NSRect? in
      guard let window = button.window else { return nil }
      return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    guard
      StatusPopoverDismissPolicy.shouldDismissClick(
        at: point,
        popoverFrame: popoverFrame,
        statusButtonFrame: statusButtonFrame
      )
    else { return }
    onDismiss?()
  }
}
