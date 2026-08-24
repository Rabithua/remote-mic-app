import SwiftUI

struct RuntimeStatusRow: View {
  let icon: String
  let title: String
  let detail: String
  let healthy: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      Image(
        systemName: healthy
          ? "checkmark.circle.fill"
          : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(healthy ? Color.green : Color.orange)
      .accessibilityHidden(true)
    }
    .padding(.horizontal, SayAllDesign.rowHorizontalPadding)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
