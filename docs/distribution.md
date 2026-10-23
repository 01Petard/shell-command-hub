# 应用交付与升级

## 用户安装

交付两个独立应用及其 ZIP：`Shell Command Hub.app` 为原生 GUI，`Shell Command Hub TUI.app` 双击后打开终端工具箱。GUI 内也能打开 TUI。

将应用拖入“应用程序”后启动即可。应用内包含工具脚本、fzf、MediaInfo 及其非系统动态库，用户不需要源码、Homebrew、Python 或开发工具。

本机产物是 Apple Silicon / arm64。当前打入的 MediaInfo 要求 macOS 15，因此本次应用最低为 macOS 15；打包器会根据所包含依赖自动计算最低系统版本。Intel 版本需要使用 Intel 依赖在相应构建环境另行构建，当前未生成 Intel/通用二进制。

## 开发者构建

```sh
./scripts/build-app.sh
/bin/bash tests/test_app_bundle.sh
```

构建需要 macOS Command Line Tools（Swift、codesign、install_name_tool、vtool）以及用于打包的 fzf、mediainfo。产物位于 `build/release/`；重复构建在验证新应用后替换构建目录中的旧产物，不修改已安装应用。

版本号统一来自 `VERSION`，写入应用元数据和 ZIP 名称。应用标识固定，用户退出旧版本后用新版 `.app` 替换即可升级。两个应用独立包含完整运行环境，可分别交付。

## 更新检查

GUI 的“检查更新”支持 HTTPS 更新源。构建时设置：

```sh
HUB_UPDATE_URL=https://your-domain.example/hub/update.json ./scripts/build-app.sh
```

更新源格式：

```json
{"version":"0.2.0","downloadURL":"https://your-domain.example/hub/download","notes":"版本说明"}
```

检测到新版本后，用户确认才打开下载页面；下载后退出并替换应用完成升级。没有配置更新源时明确显示当前版本和手动升级方式，不假装已接入在线更新。

## 对外发布

当前默认使用本地临时签名，可用于本机验证，尚未完成 Apple 公证。正式向其他用户发布前，需要开发者提供 Developer ID 签名证书，设置 `HUB_SIGN_IDENTITY` 重新构建，然后通过自己的 Apple 开发者账号提交公证并装订票据。打包器会对应用及内置可执行文件/动态库使用同一签名身份，并为正式身份启用 hardened runtime 和时间戳。

发布下载地址、更新源和 Apple 签名账号尚未配置；本次没有发布或上传任何文件，也没有修改系统安全设置。

## GUI 窗口习惯

0.2.0 使用原生侧栏导航，媒体、解压整理和端口管理分别采用文件检查器、处理计划/执行记录和进程详情布局。

红色关闭按钮及 ⌘W 关闭窗口，应用进程和任务继续运行；点击 Dock 图标可重新打开窗口。黄色按钮保持系统最小化行为。退出应用请使用 Dock 菜单中的“退出”。

应用保存窗口的大小、位置、当前功能，以及两个目录、递归选项、精确端口和 TCP/UDP 选择。退出后重新启动会恢复这些设置；显示器布局变化时会将窗口调整回可见区域。图标由内置矢量绘图脚本生成，包含从 16px 到 1024px 的 macOS 图标尺寸。
