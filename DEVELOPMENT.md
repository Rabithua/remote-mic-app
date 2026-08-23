# 开发说明 / Development

## 架构 / Architecture

| 模块 | 职责 |
| --- | --- |
| `RemoteMicApp` | AppKit 生命周期、状态栏菜单、设置窗口 |
| `BridgeAppModel` / `AppRuntimeState` | 蓝牙、音频、HID 与睡眠恢复的运行状态 |
| `AppSettings` | 映射、音频、遥控器 profile 与首次设置迁移 |
| `XiaomiBluetoothBridge` / `ATVVProtocol` | CoreBluetooth 和 RC001/RC003 语音协议 |
| `HIDRemoteMonitor` | 实体按键识别、抑制与动作分发 |
| `AudioOutput` | 16 kHz PCM 到回环音频设备 |
| `LoginItemManager` | `SMAppService.mainApp` 登录项 |

The app is a macOS 14+ Swift Package executable. Runtime and settings models are main-actor observable objects; device callbacks return to the main actor before updating UI state.

## 常用命令 / Commands

```zsh
swift test
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh dist/SayAll.app
./scripts/build-driver.sh
./scripts/verify-driver.sh dist/MiRemoteV2ch.driver
```

`build-driver.sh` clones only the pinned BlackHole revision into a restricted temporary directory and applies `third_party/blackhole/blackhole-device-usb.patch`. Do not change the pin without reviewing the upstream license, patch applicability, bundle identity, architecture, and installation rollback behavior.

## 兼容边界 / Compatibility boundaries

- Keep `SayAll.app`, executable `RemoteMic`, app bundle ID `com.hd838a.RemoteMic`, and driver bundle ID `com.hd838a.MiRemoteV2ch` stable.
- Preserve existing UserDefaults keys for audio selection, gain, remote profiles, mappings, shortcuts, custom apps, and language.
- Removed-feature keys are ignored, not erased. `onboarding.completedVersion` is read only for one-time migration to `setup.hasPresented` and `setup.completed`.
- The app remains `.accessory` and must not create a Dock icon.
- Custom-styled controls must keep their visible styling and `contentShape` inside the button label so edge and corner clicks work.

## 提交前 / Before submitting

Run `./scripts/test.sh`, then complete the physical checks in [TESTING.md](TESTING.md). Automated tests do not prove radio quality, system permission continuity, driver enumeration, or real application focus behavior.
