# 实体遥控器测试 / Physical Remote Testing

自动化先运行 `./scripts/test.sh`。以下项目必须在 Apple Silicon、macOS 14+ 真机完成；在记录中写明 macOS 版本、遥控器型号、固件标识和所用音频设备。

## 安装与身份 / Installation and identity

1. 运行 `./scripts/install-local.sh`。
2. 确认安装路径为 `/Applications/SayAll.app`，没有 Dock 图标，状态栏图标常驻。
3. 已有健康 `MiRemoteV 2ch` 时确认驱动未被替换；不兼容驱动场景确认产生带时间戳的备份。
4. 退出并再次启动，确认映射、音频设备、增益、语言和遥控器 profile 未丢失。
5. 已完成首次设置时冷启动不应出现窗口；从状态栏或再次打开 App 只显示同一个有内容的设置面板。反复使用 `⌘,` 打开、`⌘W` 关闭，不能出现空白系统 Settings 窗口；文本输入的复制、粘贴和全选仍应正常。

Pass: app and driver identifiers remain unchanged, the app launches, and existing settings survive. Fail on any unexpected overwrite, missing rollback, Dock icon, or setting loss.

## 权限 / Permissions

在没有 Xcode、未安装虚拟麦克风的新 Mac 上，仅复制完整 App：在“在这台 Mac 上设置”里授权蓝牙，点击配对入口连接 `MI RC`，再从 App 安装音频组件。验证管理员取消后可重试、安装后设备载入并自动选中、正常驱动不重装、错误身份或符号链接目标被拒绝。打开系统设置时，配对和授权窗口不能被 SayAll 设置窗口盖住。

点击“配对遥控器…”后确认 App 暂停 BLE 连接和 HID 监听；切回 App、刷新权限或睡眠唤醒都不能抢先恢复。系统配对成功或取消后，点击“继续连接”恢复；无法打开系统设置时应显示错误并恢复连接。日志包含暂停记录以及实际蓝牙错误域和错误码，不应把 App 的超时取消误报为系统认证错误。

迁移已有设置后验证“重新查找”会同时刷新记住的遥控器和新设备发现；连接失败原因保留在页面，后台扫描不覆盖正在连接/已就绪状态。“复制连接诊断”只写入本机剪贴板，并包含最近的 BLE 日志。Mac Mini 实际配对和首次安装须单独记录，不能用自动化通过代替。

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
6. TV 短按仍只切回最近 App。按住 TV 约 550 ms 后出现原生切换栏，继续按住每约 350 ms 推进一项，能到第三个及更远的 App；松开立即切换到当前项，不应停在切换栏或额外触发短按。返回键取消。重复按住与松开测试至少三次，确认 Command、Tab 最终均已释放，其他按键的原映射保持不变。
7. 按住 TV 时分别断开遥控器、关闭自定义映射、撤销权限、让 Mac 睡眠和退出 App，确认切换栏取消且 Command/Tab 不残留；丢失松键时连续持有 30 秒也应取消，不应被自动重复延长。另一只遥控器不能提交本会话，另一只已经按住方向键时不应开始，松开后可重试。已有显式 TV 长按配置（含禁用）升级后不变，设置页可改回“按住连续切换应用”。将此动作配置为已松键才识别的单击/双击时，只应执行一次快速切换，不得保持 Command。

## 音频 / Audio

选择 `MiRemoteV 2ch`，验证 16 kHz 语音、增益、测试音、设备失效后的警告与恢复。断开最后一只遥控器并等待，确认虚拟音频连接释放；重新连接后恢复。验证睡眠时不会错误中断正在排空的语音。

## 登录项 / Login item

开启“登录时启动”，注销再登录，确认只启动一个无 Dock 图标的状态栏实例。关闭后重复登录确认不启动。对“需要批准”状态，确认开关回滚并能打开系统登录项设置。

记录未完成项时必须标为“未做”，不能用单元测试、模拟 HID 或构建成功代替真机结论。
