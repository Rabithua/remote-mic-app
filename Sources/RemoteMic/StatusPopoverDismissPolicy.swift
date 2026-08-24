import CoreGraphics

enum StatusPopoverDismissPolicy {
  static func shouldDismissClick(
    at point: CGPoint,
    popoverFrame: CGRect?,
    statusButtonFrame: CGRect?
  ) -> Bool {
    guard let popoverFrame else { return false }
    if popoverFrame.contains(point) { return false }
    if statusButtonFrame?.contains(point) == true { return false }
    return true
  }
}
