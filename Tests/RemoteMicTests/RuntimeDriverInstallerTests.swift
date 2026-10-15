import Foundation
import Testing

@testable import RemoteMic

struct RuntimeDriverInstallerTests {
  @Test func bundledHealthCheckWorksOutsideTheRepositoryWithQuotedPaths() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("driver's setup \(UUID().uuidString)")
    let payload = directory.appendingPathComponent("AudioDriver")
    try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.copyItem(
      at: installerURL, to: payload.appendingPathComponent("install.sh"))
    let service = BundledAudioDriverService(resourceURL: directory)
    // Only reads the fixed system destination. No developer tools or checkout are used.
    let status = await service.status()
    #expect([AudioDriverStatus.ready, .missing, .needsRepair, .conflict].contains(status))
  }

  @Test func installerRejectsConfigurableDestinationsBeforeAnyMutation() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-f", installerURL.path, "--install", "/tmp/not-an-install-destination"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 64)
  }

  @Test func verifierRejectsASymlinkedBundle() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("driver-link-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let link = directory.appendingPathComponent("MiRemoteV2ch.driver")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-f", installerURL.path, "--verify-bundle", link.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus != 0)
  }

  private var installerURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/AudioDriver/install.sh")
  }
}
