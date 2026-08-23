# Repository rules

- This fork targets Apple Silicon and macOS 14 or later only.
- Keep the app menu-bar-only with `NSApplication.ActivationPolicy.accessory`.
- Preserve `SayAll.app`, executable `RemoteMic`, bundle ID `com.hd838a.RemoteMic`, driver ID `com.hd838a.MiRemoteV2ch`, and retained UserDefaults keys.
- Do not reintroduce phone, Apple Watch, web remote, analytics, transcripts/MCP, macros, private packages, Sparkle, Intel builds, or release packaging.
- Build scripts must remain safe for their explicit app and driver destinations; never weaken bundle-ID, symlink, architecture, or rollback guards.
- For custom-styled controls, place visible styling and `contentShape` inside the `Button` label and test edge/corner hit targets.
- Run `./scripts/test.sh` before merging. Treat real Bluetooth, HID, audio, permission continuity, and sleep/wake checks in `TESTING.md` as separate manual acceptance work.
- Only submit changes to `Rabithua/remote-mic-app`; do not open pull requests against the upstream repository.
