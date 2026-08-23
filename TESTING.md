# 实体遥控器测试 / Physical Remote Testing

自动化先运行 `./scripts/test.sh`。以下项目必须在 Apple Silicon、macOS 14+ 真机完成；在记录中写明 macOS 版本、遥控器型号、固件标识和所用音频设备。

## 安装与身份 / Installation and identity

1. 运行 `./scripts/install-local.sh`。
2. 确认安装路径为 `/Applications/SayAll.app`，没有 Dock 图标，状态栏图标常驻。
3. 已有健康 `MiRemoteV 2ch` 时确认驱动未被替换；不兼容驱动场景确认产生带时间戳的备份。
4. 退出并再次启动，确认映射、音频设备、增益、语言和遥控器 profile 未丢失。

Pass: app and driver identifiers remain unchanged, the app launches, and existing settings survive. Fail on any unexpected overwrite, missing rollback, Dock icon, or setting loss.

## 权限 / Permissions

1. 在干净权限状态分别授权蓝牙、输入监控、辅助功能。
2. 每次授权后重启应用，确认权限页和状态菜单一致。
3. 从旧版升级，确认系统仍把权限归属到同一应用身份。

Pass: missing permissions show warnings without reopening Settings after the first presentation; granted permissions become healthy after the required restart.

## RC001 与 RC003 / RC001 and RC003

对每个型号分别验证：连接、设备名称、电量（设备支持时）、语音开始、连续 PCM、松开后排空、断开重连、Mac 睡眠唤醒。语音在 QuickTime 或目标听写 App 中应有完整开头和结尾，无第二次才工作的现象。

For RC003, also verify the measured TV key and power-key suppression. For RC001, verify short voice streams do not lose their tail.

## 按键和多遥控器 / Buttons and multiple remotes

1. 给每个可见按钮分别设置单击、双击、长按，验证时序互不串扰。
2. 验证方向键、确定、返回、主页、菜单、TV、电源和音量键；需要按住重复的键也要验证 key-up。
3. 配对两只遥控器，设置不同 profile，确认映射不会跨设备。
4. 验证自定义快捷键、自定义 App 仅打开、激活后发送快捷键和记录输入框。
5. 点击设置中每个自定义按钮的中心、四边和四角，整个可见表面都必须触发同一动作。

## 音频 / Audio

选择 `MiRemoteV 2ch`，验证 16 kHz 语音、增益、测试音、设备失效后的警告与恢复。断开最后一只遥控器并等待，确认虚拟音频连接释放；重新连接后恢复。验证睡眠时不会错误中断正在排空的语音。

## 登录项 / Login item

开启“登录时启动”，注销再登录，确认只启动一个无 Dock 图标的状态栏实例。关闭后重复登录确认不启动。对“需要批准”状态，确认开关回滚并能打开系统登录项设置。

记录未完成项时必须标为“未做”，不能用单元测试、模拟 HID 或构建成功代替真机结论。
