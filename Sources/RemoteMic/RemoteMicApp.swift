import AppKit

@main
enum RemoteMicApp {
  @MainActor
  static func main() {
    #if DEBUG
      if CommandLine.arguments.contains("--verify-tv-hold") {
        TVHoldVerification.run()
        return
      }
    #endif
    let application = NSApplication.shared
    let appDelegate = RemoteMicAppDelegate()
    application.delegate = appDelegate
    withExtendedLifetime(appDelegate) {
      application.run()
    }
  }
}
