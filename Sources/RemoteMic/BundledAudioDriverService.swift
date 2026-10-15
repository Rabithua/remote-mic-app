import Foundation

/// Serializes privilege prompts and runs the bundled installer without blocking the UI actor.
actor BundledAudioDriverService: AudioDriverServicing {
  private let resourceURL: URL?

  init(resourceURL: URL? = Bundle.main.resourceURL) {
    self.resourceURL = resourceURL
  }

  func status() async -> AudioDriverStatus {
    guard let script = installerURL else { return .unavailable }
    do {
      let result = try await run("/bin/zsh", arguments: ["-f", script.path, "--check"])
      switch result.code {
      case 0: return .ready
      case 10: return .missing
      case 11: return .needsRepair
      case 12: return .conflict
      default: return .unavailable
      }
    } catch {
      return .unavailable
    }
  }

  func install() async throws {
    guard let script = installerURL else { throw CocoaError(.fileNoSuchFile) }
    // Arguments are passed through Process and AppleScript's quoted form, never interpolated
    // into executable shell text. macOS owns the password dialog; the app never sees credentials.
    let appleScript = """
      on run argv
        do shell script "/bin/zsh -f " & quoted form of (item 1 of argv) & " --install" with administrator privileges
      end run
      """
    let result = try await run(
      "/usr/bin/osascript", arguments: ["-e", appleScript, script.path]
    )
    if result.code != 0 {
      if result.output.contains("(-128)") { throw CancellationError() }
      throw NSError(
        domain: "RemoteMic.AudioDriver", code: Int(result.code),
        userInfo: [NSLocalizedDescriptionKey: result.output]
      )
    }
  }

  private var installerURL: URL? {
    guard let resourceURL else { return nil }
    let url = resourceURL.appendingPathComponent("AudioDriver/install.sh")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  private func run(_ executable: String, arguments: [String]) async throws -> Result {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    return try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { completed in
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        continuation.resume(
          returning: Result(
            code: completed.terminationStatus, output: String(decoding: data, as: UTF8.self))
        )
      }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
  }

  private struct Result: Sendable {
    let code: Int32
    let output: String
  }
}
