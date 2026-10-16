# SayAll · Personal Menu Bar Edition

[简体中文](README.md)

This is a trimmed personal fork of [HD838A/remote-mic-app](https://github.com/HD838A/remote-mic-app). It turns a compatible Xiaomi Bluetooth voice remote into a wireless Mac microphone and button controller, with only the physical-remote path retained.

## Features

- Menu-bar-only app with no Dock icon or persistent main window. Either click opens the status menu.
- RC001, RC003, ATVV voice, HID buttons, reconnect, and sleep/wake recovery.
- Separate single-click, double-click, and long-press mappings, custom shortcuts, custom apps, and multiple remote profiles.
- Three compact settings pages: Connection & Audio, Button Mapping, and Permissions.
- Local logs and launch at login. No phone, Apple Watch, web remote, analytics, transcripts/MCP, macros, or in-app updater.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- The complete app requires no Xcode or Terminal; building from source requires full Xcode and network access
- A compatible Xiaomi Bluetooth voice remote, primarily tested with RC001 and RC003

## Install

Copy the complete `SayAll.app` into Applications and open it. Under Connection & Audio → Set up this Mac, allow Bluetooth, pair the remote, and install the bundled `MiRemoteV 2ch` audio component. Install / Repair uses the standard macOS administrator prompt; no driver download or Terminal command is needed. Healthy drivers are preserved; repairs back up the old driver without overwriting a component with a different identity.

For developers building and installing from source:

```zsh
./scripts/install-local.sh
```

The script builds and verifies `SayAll.app`, then atomically replaces `/Applications/SayAll.app`. A healthy installed `MiRemoteV 2ch` driver is preserved. If the driver is missing or incompatible, it is built from a pinned BlackHole commit and the old driver is backed up before replacement. macOS requests administrator authorization once during installation.

The script refuses to overwrite a same-named app or driver with a different bundle identifier. Run the same command for future updates; there is no in-app updater.

To build or run without installing:

```zsh
./scripts/build-app.sh
./scripts/run-local.sh
```

## Use

1. Launch SayAll and allow Bluetooth under Set up this Mac.
2. Click Pair Remote… and connect `MI RC` or the Xiaomi remote in system Bluetooth settings. SayAll pauses automatic connections until you return and click Continue Connecting. For 2 Pro, hold Home and Menu together to pair; check the manual for other models. Disconnect the old Mac before switching computers.
3. Click Install / Repair for the virtual microphone. First setup selects `MiRemoteV 2ch` automatically; existing audio preferences, including a disabled output, are preserved. Other loopback devices remain available. Input Monitoring and Accessibility permissions for button mapping are accessible from the same page.
4. Select the same microphone in the dictation app. Hold the remote voice button to speak and release it to stop.
5. Switch mappings from the status menu or open Settings for click, double-click, long-press, and multi-remote configuration.

By default, a short TV press switches to the previous app. Hold TV for about half a second to show the running-app selection strip, release TV, then use Left/Right to select, OK to switch, or Back to cancel. Selection wraps around and does not synthesize a held Command key. It cancels after 30 idle seconds, on disconnect, sleep, or quit. Existing custom TV long-press mappings remain unchanged; choose or disable Browse Apps in button settings.

The app does not change the system's default input or output device, store voice audio, or upload it. Missing permissions, a disconnected remote, or an invalid audio device produce status-menu warnings instead of repeatedly opening Settings.

Pairing, permissions, and drivers must be configured on each Mac. If the remote is absent from system Bluetooth, check pairing mode. If the system is connected but SayAll is not ready, click Search Again. Copy Connection Diagnostics puts permission, connection, audio, and recent log details on the local clipboard, without Terminal commands or automatic uploads.

## Development and testing

- [Development guide](DEVELOPMENT.md)
- [Physical remote test guide](TESTING.md)

Run the complete automated check with:

```zsh
./scripts/test.sh
```

## License and attribution

The software and derived driver are released under `GPL-3.0-only`. See [LICENSE.md](LICENSE.md), [COPYRIGHT.en.md](COPYRIGHT.en.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). This fork does not include the upstream proprietary app logo.

The driver is derived from [ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole) at pinned commit `e2b22aaaba4e507a097131704bf96dabc004d9cf`, uses a separate bundle identifier, and does not replace BlackHole.
