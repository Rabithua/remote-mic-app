import SwiftUI

struct RemoteProfileRow: View {
  let connected: Bool
  let selected: Bool
  let batteryLevel: Int?
  let displayName: String
  let connectedText: String
  let disconnectedText: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: connected ? "remote.fill" : "remote")
          .foregroundStyle(connected ? Color.accentColor : Color.secondary)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(displayName)
            .font(.callout.weight(.medium))
          HStack(spacing: 5) {
            Text(connected ? connectedText : disconnectedText)
            if let batteryLevel {
              Text("· \(batteryLevel)%")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)
        if selected {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
        }
      }
      .padding(.horizontal, SayAllDesign.rowHorizontalPadding)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(
        selected ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear)
      )
    }
    .buttonStyle(.plain)
  }
}
