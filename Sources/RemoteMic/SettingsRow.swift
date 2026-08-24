import SwiftUI

struct SettingsRow<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    HStack(spacing: 12) {
      content
    }
    .padding(.horizontal, SayAllDesign.rowHorizontalPadding)
    .padding(.vertical, SayAllDesign.rowVerticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
