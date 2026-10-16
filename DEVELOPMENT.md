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

### TV 持有的真实验证 / Live TV-hold verification

Debug builds provide an explicit `--verify-tv-hold` runner; Release builds have no such entry point. Build using `CONFIGURATION=debug ./scripts/build-app.sh`, then run `dist/SayAll.app/Contents/MacOS/RemoteMic --verify-tv-hold` in an interactive terminal. Existing Accessibility permission is required; it does not prompt or alter TCC.

The runner uses an isolated temporary preferences suite, the real HID parser and gesture recognizer, production timers, and real CGEvent output. It never starts Bluetooth, audio, or a physical HID manager. Do not use the physical remote during verification. Send one command at a time and wait for the after-stage result: `cycle 1250`, `cycle 1600`, `cycle 1950` simulate different hold durations; `cancel 1250` and `disconnect 1250` must preserve the frontmost app. Verify actual frontmost PIDs/apps, reaching at least three apps rather than merely trusting event-post logs; confirm no Command/Tab remains down after each run. `quit`, EOF, or the three-minute watchdog cancels the session and removes the temporary suite. The runner attempts to restore the original frontmost app on exit; verify focus separately. Simulated HID reports do not prove the physical Bluetooth device's native event timing.

Add `--with-native-tv-events` to replay the non-seized path as well: it starts the production keyboard suppressor, opens an isolated input-sink window, and injects untagged native TV down/repeat/up alongside the HID reports. The replay preserves the event source's live modifier flags, adding RC003's measured non-coalesced bit; forcing its flags-at-rest (`0x100`) while Command is held would manufacture a modifier reset. Start a fresh runner for each case and verify that its test window is frontmost; the runner refuses native replay otherwise, so failed suppression cannot type into user documents. No `VERIFY FAIL native TV event leaked` should occur. Check the actual switched PID, cancellation, and held-stage focus again. This is still simulated native input, not proof of physical Bluetooth timing.

Only this DEBUG native-event verification mode temporarily uses a regular foreground test window (and a Dock icon) so the safety guard can verify its PID. Normal launches and Release builds remain accessory/status-bar-only; quitting the runner removes the test window and icon.
