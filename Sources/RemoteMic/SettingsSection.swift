import SwiftUI

struct SettingsSection<Content: View>: View {
  let title: String
  private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, SayAllDesign.sectionHorizontalPadding)
      .padding(.vertical, SayAllDesign.sectionVerticalPadding)
      .background(.quinary)

      content
    }
  }
}
