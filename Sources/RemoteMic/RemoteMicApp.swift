import SwiftUI

@main
struct RemoteMicApp: App {
  @NSApplicationDelegateAdaptor(RemoteMicAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
