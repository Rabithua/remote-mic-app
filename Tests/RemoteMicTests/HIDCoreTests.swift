import Foundation
import Testing

@testable import RemoteMic

@Suite("HID core")
struct HIDCoreTests {
  @Test func reportsDecodeButtonsAndRejectWrongReportID() {
    let data = Data([
      UInt8(RemoteButton.ok.hidUsage & 0xFF),
      UInt8(RemoteButton.ok.hidUsage >> 8),
      UInt8(RemoteButton.tv.hidUsage & 0xFF),
      UInt8(RemoteButton.tv.hidUsage >> 8),
    ])
    let usages = RemoteHIDReportParser.usages(reportID: 1, data: data)

    #expect(usages == [RemoteButton.ok.hidUsage, RemoteButton.tv.hidUsage])
    #expect(RemoteButton.buttons(for: usages ?? []) == [.ok, .tv])
    #expect(RemoteHIDReportParser.usages(reportID: 2, data: data) == nil)
  }

  @Test func mappingFailsClosedUntilBothPermissionsAndPowerSuppressionAreReady() {
    #expect(
      !HIDPermissionGate.canMonitor(
        mappingEnabled: true,
        inputMonitoringGranted: false,
        accessibilityGranted: true,
        powerKeySuppressed: true
      ))
    #expect(
      !HIDPermissionGate.canMonitor(
        mappingEnabled: true,
        inputMonitoringGranted: true,
        accessibilityGranted: false,
        powerKeySuppressed: true
      ))
    #expect(
      !HIDPermissionGate.canMonitor(
        mappingEnabled: true,
        inputMonitoringGranted: true,
        accessibilityGranted: true,
        powerKeySuppressed: false
      ))
    #expect(
      HIDPermissionGate.canMonitor(
        mappingEnabled: true,
        inputMonitoringGranted: true,
        accessibilityGranted: true,
        powerKeySuppressed: true
      ))
  }

  @Test func rc003MeasuredTVKeyAndPowerSuppressionStayStable() {
    #expect(RemoteButton.tv.nativeEvent == .keyboard(keyCode: 10))
    #expect(RemoteButton.power.nativeEvent == .keyboard(keyCode: 90))
    #expect(
      RemoteVoiceFunctionMappingPolicy.suppressedRemotePowerKey.destination
        == 0x0000_0007_0000_006F)
  }

  @Test func rc001AndRc003ModelIdentifiersAreRecognized() {
    #expect(XiaomiRemoteModel.identified(by: "RC001") == .rc001)
    #expect(XiaomiRemoteModel.identified(by: "RC003") == .rc003)
    #expect(XiaomiRemoteModel.identified(by: "ARN9") == .rc003)
    #expect(XiaomiRemoteModel.identified(by: "other") == nil)
  }
}
