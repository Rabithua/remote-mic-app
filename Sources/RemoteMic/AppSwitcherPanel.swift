import AppKit

@MainActor
final class RunningApplicationCatalog {
  private static let shared = RunningApplicationCatalog()
  private var recentProcesses: [pid_t] = []
  private var activationObserver: NSObjectProtocol?

  private init() {
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else { return }
      let pid = app.processIdentifier
      Task { @MainActor [weak self] in
        guard let self else { return }
        recentProcesses.removeAll { $0 == pid }
        recentProcesses.insert(pid, at: 0)
        recentProcesses = Array(recentProcesses.prefix(100))
      }
    }
  }

  static func snapshot() -> [AppSwitcherApplication] {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let recent = shared.recentProcesses
    return NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleURL != nil
    }.sorted {
      if $0.processIdentifier == $1.processIdentifier { return false }
      if $0.processIdentifier == front { return true }
      if $1.processIdentifier == front { return false }
      let left = recent.firstIndex(of: $0.processIdentifier) ?? Int.max
      let right = recent.firstIndex(of: $1.processIdentifier) ?? Int.max
      if left != right { return left < right }
      return ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast)
    }.compactMap {
      guard let url = $0.bundleURL else { return nil }
      return AppSwitcherApplication(
        processIdentifier: $0.processIdentifier,
        bundleIdentifier: $0.bundleIdentifier ?? url.path,
        name: $0.localizedName ?? url.deletingPathExtension().lastPathComponent,
        bundleURL: url)
    }
  }

  static func activate(_ target: AppSwitcherApplication) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: target.processIdentifier),
      !app.isTerminated, app.bundleURL == target.bundleURL
    else { return false }
    return app.activate(options: [.activateAllWindows])
  }
}

/// Non-activating: displaying or cancelling it must never change the frontmost app.
@MainActor
final class AppSwitcherPanel: AppSwitcherPresenting {
  private let localizedText: (String) -> String
  private var panel: NSPanel?
  private var tiles: [NSView] = []
  private var title: NSTextField?
  private var applications: [AppSwitcherApplication] = []

  init(
    localizedText: @escaping (String) -> String = { key in
      let fallback =
        [
          "app_switcher.title": "Choose an App",
          "app_switcher.hint": "← → Select · OK Switch · Back Cancel",
          "app_switcher.selected": "Selected",
        ][key] ?? key
      return NSLocalizedString(key, value: fallback, comment: "")
    }
  ) {
    self.localizedText = localizedText
  }

  func show(applications: [AppSwitcherApplication], selectedIndex: Int) {
    dismiss()
    guard !applications.isEmpty,
      let screen = NSScreen.screens.first(where: {
        NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
      })
        ?? NSScreen.main
    else { return }
    self.applications = applications
    let width = min(max(320, CGFloat(applications.count) * 88 + 40), screen.visibleFrame.width - 80)
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 164),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = localizedText("app_switcher.title")
    panel.identifier = NSUserInterfaceItemIdentifier("SayAllAppSwitcher")
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .popUpMenu
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

    let background = NSVisualEffectView(frame: panel.contentView!.bounds)
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 20
    background.layer?.masksToBounds = true
    panel.contentView = background

    let scroll = NSScrollView(frame: NSRect(x: 20, y: 56, width: width - 40, height: 88))
    scroll.drawsBackground = false
    scroll.hasHorizontalScroller = false
    scroll.hasVerticalScroller = false
    let contentWidth = CGFloat(applications.count) * 88
    let stripWidth = max(width - 40, contentWidth)
    let strip = NSView(frame: NSRect(x: 0, y: 0, width: stripWidth, height: 88))
    let leading = (stripWidth - contentWidth) / 2
    for (index, app) in applications.enumerated() {
      let tile = NSView(
        frame: NSRect(x: leading + CGFloat(index) * 88, y: 0, width: 88, height: 88))
      tile.wantsLayer = true
      tile.layer?.cornerRadius = 14
      tile.setAccessibilityElement(true)
      tile.setAccessibilityRole(.image)
      tile.setAccessibilityLabel(app.name)
      let icon = NSImageView(frame: NSRect(x: 12, y: 12, width: 64, height: 64))
      icon.image = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
      icon.imageScaling = .scaleProportionallyUpOrDown
      tile.addSubview(icon)
      strip.addSubview(tile)
      tiles.append(tile)
    }
    scroll.documentView = strip
    background.addSubview(scroll)

    let title = NSTextField(labelWithString: "")
    title.frame = NSRect(x: 16, y: 30, width: width - 32, height: 20)
    title.alignment = .center
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.lineBreakMode = .byTruncatingTail
    background.addSubview(title)
    self.title = title
    let hint = NSTextField(labelWithString: localizedText("app_switcher.hint"))
    hint.frame = NSRect(x: 12, y: 10, width: width - 24, height: 16)
    hint.alignment = .center
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    background.addSubview(hint)
    self.panel = panel
    select(index: selectedIndex)
    let frame = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.midY - 82))
    panel.orderFrontRegardless()
  }

  func select(index: Int) {
    guard applications.indices.contains(index) else { return }
    for (position, tile) in tiles.enumerated() {
      tile.layer?.backgroundColor =
        position == index
        ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : NSColor.clear.cgColor
      tile.setAccessibilityValue(position == index ? localizedText("app_switcher.selected") : "")
    }
    title?.stringValue = applications[index].name
    tiles[index].scrollToVisible(tiles[index].bounds)
  }

  func dismiss() {
    panel?.orderOut(nil)
    panel = nil
    tiles = []
    title = nil
    applications = []
  }
}
