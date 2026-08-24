import CoreGraphics
import Testing

@testable import RemoteMic

@Suite("Status popover dismissal")
struct StatusPopoverDismissPolicyTests {
  private let popoverFrame = CGRect(x: 400, y: 300, width: 340, height: 560)
  private let statusButtonFrame = CGRect(x: 550, y: 870, width: 24, height: 24)

  @Test func clickInsidePopoverStaysOpen() {
    #expect(
      !StatusPopoverDismissPolicy.shouldDismissClick(
        at: CGPoint(x: 570, y: 580),
        popoverFrame: popoverFrame,
        statusButtonFrame: statusButtonFrame
      )
    )
  }

  @Test func clickOnStatusButtonIsLeftForTheToggleAction() {
    #expect(
      !StatusPopoverDismissPolicy.shouldDismissClick(
        at: CGPoint(x: 562, y: 882),
        popoverFrame: popoverFrame,
        statusButtonFrame: statusButtonFrame
      )
    )
  }

  @Test func clickOutsidePopoverAndStatusButtonDismisses() {
    #expect(
      StatusPopoverDismissPolicy.shouldDismissClick(
        at: CGPoint(x: 100, y: 100),
        popoverFrame: popoverFrame,
        statusButtonFrame: statusButtonFrame
      )
    )
  }

  @Test func missingPopoverWindowDoesNotDismissPrematurely() {
    #expect(
      !StatusPopoverDismissPolicy.shouldDismissClick(
        at: CGPoint(x: 100, y: 100),
        popoverFrame: nil,
        statusButtonFrame: statusButtonFrame
      )
    )
  }
}
