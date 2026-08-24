import SwiftUI

struct SettingsWindowHeader: View {
  let title: String
  let closeLabel: String
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.headline)

      Spacer(minLength: 0)

      Button(action: onClose) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(closeLabel)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}
