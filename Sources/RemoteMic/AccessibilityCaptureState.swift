import SwiftUI

enum AccessibilityCaptureState: Equatable {
  case idle
  case recording
  case failed
  case succeeded

  var color: Color {
    switch self {
    case .idle: return .secondary
    case .recording: return .orange
    case .failed: return .red
    case .succeeded: return .green
    }
  }
}
