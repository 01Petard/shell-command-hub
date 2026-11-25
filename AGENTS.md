# Shell Command Hub

Swift/AppKit 原生应用与 Zsh 终端工具入口。

- `app/` 提供 macOS 界面与 TUI 启动入口。见 [应用结构](app/AGENTS.md)。
- `hub` 读取 `catalog.tsv`，通过 `lib/` 调用 `tools/` 中的命令。
- `scripts/` 构建包含 TUI 的 GUI 应用包，`tests/` 验证应用与命令交互。
- `docs/` 记录工具用法与应用交付方式。
