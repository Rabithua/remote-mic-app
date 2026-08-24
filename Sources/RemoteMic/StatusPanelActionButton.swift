import SwiftUI

struct StatusPanelActionButton: View {
  let title: String
  let systemImage: String
  var trailingSystemImage: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .foregroundStyle(.secondary)
          .frame(width: 18)
        Text(title)
        Spacer(minLength: 8)
        if let trailingSystemImage {
          Image(systemName: trailingSystemImage)
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, SayAllDesign.rowHorizontalPadding)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
