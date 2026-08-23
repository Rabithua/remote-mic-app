# Copyright

[English](COPYRIGHT.en.md)

**SayAll**

Copyright (C) 2026 SayAll contributors

本程序是一个 macOS 适配版本，其实现参考了 GPL-3.0-only 项目 [xxb26553663-star/remote-bridge-hub](https://github.com/xxb26553663-star/remote-bridge-hub)，参考提交为 `8a93f321ac71a602300c6cd77f7256fa4b63068e`。

本项目的改动包括：

- 纯状态栏的原生 SwiftUI/AppKit macOS 应用；
- CoreBluetooth 连接与状态管理；
- CoreAudio 输出设备选择；
- IOHID 权限、按键读取与 macOS 动作注入；
- macOS 构建、测试和本地安装流程；
- 从固定 BlackHole 源码构建的 `MiRemoteV2ch.driver` 豆包兼容方案。

本适配作品的软件代码按 `GPL-3.0-only` 发布。完整许可见 [LICENSE.md](LICENSE.md)，第三方来源和归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

上游专有 App Logo 不包含在这个修改后的 fork 中。菜单栏状态图标和程序代码按仓库所附软件许可处理。
