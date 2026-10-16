import Testing

@testable import RemoteMic

@MainActor
struct SystemBluetoothPairingCoordinatorTests {
  @Test func connectionsAreSuspendedBeforeOpeningSettingsAndResumeOnlyOnce() {
    var events: [String] = []
    let coordinator = SystemBluetoothPairingCoordinator(
      suspendConnections: { events.append("suspend") },
      resumeConnections: { events.append("resume") },
      openSettings: {
        events.append("open")
        return true
      }
    )
    #expect(coordinator.begin())
    #expect(events == ["suspend", "open"])
    #expect(coordinator.isActive)
    // Reopening the system pane must not restart discovery or suspend twice.
    #expect(coordinator.begin())
    #expect(events == ["suspend", "open", "open"])
    coordinator.resume()
    coordinator.resume()
    #expect(events == ["suspend", "open", "open", "resume"])
    #expect(coordinator.isActive == false)
  }

  @Test func failureToOpenSettingsRestoresAutomaticConnections() {
    var events: [String] = []
    let coordinator = SystemBluetoothPairingCoordinator(
      suspendConnections: { events.append("suspend") },
      resumeConnections: { events.append("resume") },
      openSettings: {
        events.append("open")
        return false
      }
    )
    #expect(coordinator.begin() == false)
    #expect(coordinator.isActive == false)
    #expect(events == ["suspend", "open", "resume"])
  }

  @Test func failedReopenKeepsExistingPairingSessionPaused() {
    var canOpen = true
    var resumes = 0
    let coordinator = SystemBluetoothPairingCoordinator(
      suspendConnections: {},
      resumeConnections: { resumes += 1 },
      openSettings: { canOpen }
    )
    #expect(coordinator.begin())
    canOpen = false
    #expect(coordinator.begin() == false)
    #expect(coordinator.isActive)
    #expect(resumes == 0)
    coordinator.resume()
    #expect(resumes == 1)
  }
}
