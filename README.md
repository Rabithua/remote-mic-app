# 无线麦 · 个人状态栏版

[English](README.en.md)

这是 [HD838A/remote-mic-app](https://github.com/HD838A/remote-mic-app) 的个人精简 fork。它把兼容的小米蓝牙语音遥控器变成 Mac 的无线麦克风和快捷键控制器，只保留实体遥控器路径。

## 特点

- 纯状态栏工具：无 Dock 图标、无常驻主窗口，左右点击状态栏图标都可打开菜单。
- 支持 RC001、RC003、ATVV 语音、HID 按键、断线重连和睡眠唤醒。
- 每个按钮可分别配置单击、双击和长按，支持自定义快捷键、自定义 App 和多遥控器配置。
- 三个紧凑设置页：连接与音频、按键映射、权限。
- 本机日志和登录时启动；不包含手机、Apple Watch、Web、统计、回眸/MCP、宏或应用内更新。

## 要求

- Apple Silicon Mac
- macOS 14 或更高版本
- Xcode 命令行工具；从源码构建兼容驱动时需要完整 Xcode 和网络连接
- 兼容的小米蓝牙语音遥控器（主要验证 RC001 / RC003）

## 安装

```zsh
./scripts/install-local.sh
```

脚本会构建并验证 `SayAll.app`，再原子替换 `/Applications/SayAll.app`。如果已安装的 `MiRemoteV 2ch` 驱动健康，会原样保留；缺失或不兼容时，脚本会从固定 BlackHole 提交构建驱动，并在安装前备份旧驱动。安装时 macOS 会请求一次管理员授权。

同名 App 或驱动的 Bundle ID 不匹配时，脚本会拒绝覆盖。后续更新仍运行同一命令，不使用应用内更新。

只构建或临时运行：

```zsh
./scripts/build-app.sh
./scripts/run-local.sh
```

## 使用

1. 在系统设置中配对遥控器并启动 SayAll。
2. 首次出现精简设置时允许蓝牙；需要按键映射时再允许输入监控和辅助功能。
3. 在“连接与音频”中选择 `MiRemoteV 2ch` 或其他回环音频设备。
4. 在听写应用中选择同一设备作为麦克风，按住遥控器语音键说话，松开结束。
5. 从状态栏菜单快速切换映射，或打开完整设置修改单击、双击、长按和多遥控器配置。

应用不会自动修改系统默认输入或输出设备，也不会保存或上传语音。权限缺失、遥控器未连接或音频设备失效时，应用只在状态栏菜单显示警告，不会反复弹出设置。

## 开发与测试

- [开发说明](DEVELOPMENT.md)
- [实体遥控器测试说明](TESTING.md)

运行完整自动化验证：

```zsh
./scripts/test.sh
```

## 许可与来源

软件代码和派生驱动按 `GPL-3.0-only` 发布。完整条款与归属见 [LICENSE.md](LICENSE.md)、[COPYRIGHT.md](COPYRIGHT.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。本 fork 不包含上游专有 App Logo。

驱动由 [ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole) 固定提交 `e2b22aaaba4e507a097131704bf96dabc004d9cf` 派生构建，使用独立 Bundle ID，不覆盖 BlackHole。
