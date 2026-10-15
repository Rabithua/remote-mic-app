import AppKit

@main
enum RemoteMicApp {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let appDelegate = RemoteMicAppDelegate()
    application.delegate = appDelegate
    withExtendedLifetime(appDelegate) {
      application.run()
    }
  }
}
