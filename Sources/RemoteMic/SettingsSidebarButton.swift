import SwiftUI

struct SettingsSidebarButton: View {
  let title: String
  let systemImage: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: systemImage)
          .frame(width: 18)
        Text(title)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
      .contentShape(Rectangle())
      .background(
        isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: SayAllDesign.compactCornerRadius)
      )
    }
    .buttonStyle(.plain)
  }
}
