import SwiftUI

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let granted: Bool
  let grantedText: String
  let pendingText: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 17))
        .foregroundStyle(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      Label(
        granted ? grantedText : pendingText,
        systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
      )
      .font(.caption)
      .foregroundStyle(granted ? Color.green : Color.orange)

      Button(action: action) {
        Text(actionTitle)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .contentShape(Rectangle())
      }
      .controlSize(.small)
    }
    .padding(.horizontal, SayAllDesign.rowHorizontalPadding)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
