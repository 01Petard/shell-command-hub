import AppKit
import Foundation

let bundle = Bundle.main
let resources = bundle.resourceURL!
let toolbox = resources.appendingPathComponent("toolbox")
let runtime = resources.appendingPathComponent("runtime/bin")
let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1"
func environment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = runtime.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
    env["NO_COLOR"] = "1"
    return env
}
func terminalLaunch() throws {
    guard NSWorkspace.shared.open(resources.appendingPathComponent("launch-tui.command")) else {
        throw NSError(domain: "HubTerminal", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开内置终端启动器。"])
    }
}

if CommandLine.arguments.contains("--self-test") {
    var ok = true
    for (name, flag) in [("fzf", "--version"), ("mediainfo", "--Version")] {
        let p = Process(); p.executableURL = runtime.appendingPathComponent(name); p.arguments = [flag]; p.environment = environment()
        do { try p.run(); p.waitUntilExit(); ok = ok && p.terminationStatus == 0 } catch { print(error); ok = false }
    }
    for path in ["hub", "lib/tool-tui.zsh", "tools/network/port-info.sh", "tools/archive/zip-tidy.sh", "tools/media/videoinfo_beauty.sh"] {
        ok = ok && FileManager.default.fileExists(atPath: toolbox.appendingPathComponent(path).path)
    }
    ok = ok && NSImage(contentsOf: resources.appendingPathComponent("HubIcon.icns")) != nil
    print("Shell Command Hub \(appVersion): bundled runtime \(ok ? "OK" : "FAILED")")
    exit(ok ? 0 : 1)
}

func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: value)
    field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
}
func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 10) -> NSStackView {
    let view = NSStackView(views: views); view.orientation = vertical ? .vertical : .horizontal
    view.alignment = vertical ? .leading : .centerY; view.spacing = spacing; view.distribution = .fill
    return view
}
func pin(_ view: NSView, in parent: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
    NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
}
func symbol(_ name: String, description: String, size: CGFloat = 18) -> NSImageView {
    let image = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage())
    image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    image.contentTintColor = .secondaryLabelColor
    image.widthAnchor.constraint(equalToConstant: size + 4).isActive = true
    image.heightAnchor.constraint(equalToConstant: size + 4).isActive = true
    return image
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class HubApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let defaults = UserDefaults.standard
    let sidebar = NSTableView()
    let workspace = NSView()
    let mediaPage = NSView(), archivePage = NSView(), portsPage = NSView()
    let names = ["媒体信息", "解压整理", "端口管理"]
    let icons = ["play.rectangle", "shippingbox", "network"]
    let mediaInput = NSTextField(), archiveInput = NSTextField(), portInput = NSTextField()
    let mediaChoose = NSButton(title: "选择目录…", target: nil, action: nil)
    let archiveChoose = NSButton(title: "选择目录…", target: nil, action: nil)
    let mediaRefresh = NSButton(title: "重新扫描", target: nil, action: nil)
    let archiveRefresh = NSButton(title: "更新计划", target: nil, action: nil)
    let portRefresh = NSButton(title: "查询", target: nil, action: nil)
    let recursive = NSButton(checkboxWithTitle: "包含子目录", target: nil, action: nil)
    let mediaSearch = NSSearchField()
    let proto = NSSegmentedControl(labels: ["TCP 监听", "UDP 绑定"], trackingMode: .selectOne, target: nil, action: nil)
    let mediaTable = NSTableView(), archiveTable = NSTableView(), portTable = NSTableView()
    let inspector = NSStackView()
    let mediaCount = text("尚未扫描", size: 12, color: .secondaryLabelColor)
    let mediaStatus = text("输入目录路径或选择一个文件夹。", size: 12, color: .secondaryLabelColor)
    let archiveCount = text("处理计划", size: 14, weight: .semibold)
    let archiveStatus = text("预览不会修改文件。", size: 12, color: .secondaryLabelColor)
    let portCount = text("", size: 12, color: .secondaryLabelColor)
    let portStatus = text("选择一个进程，查看启动来源。", size: 12, color: .secondaryLabelColor)
    let archiveLog = NSTextView()
    let archiveProgress = NSProgressIndicator()
    let archiveAction = NSButton(title: "开始整理…", target: nil, action: nil)
    let archiveCancel = NSButton(title: "中止整理", target: nil, action: nil)
    let portAction = NSButton(title: "终止进程…", target: nil, action: nil)
    var portValues: [String: NSTextField] = [:]
    var tool = 0
    var mediaFiles: [String] = [], visibleMedia: [String] = [], archives: [String] = [], ports: [[String]] = []
    var mediaCache: [String: Data] = [:]
    var mediaDirectory = NSHomeDirectory(), archiveDirectory = NSHomeDirectory(), portQuery = ""
    var process: Process?
    var busy = false, archiveRunning = false, quitting = false, restoring = true
    var currentStatus: NSTextField { [mediaStatus, archiveStatus, portStatus][tool] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSImage(contentsOf: resources.appendingPathComponent("HubIcon.icns"))
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Shell Command Hub", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "检查更新…", action: #selector(checkUpdates), keyEquivalent: "")
        appMenu.addItem(withTitle: "打开终端 TUI", action: #selector(openTerminal), keyEquivalent: "")
        appMenu.addItem(.separator())
        let close = appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); close.target = window
        item.submenu = appMenu
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        editItem.submenu = edit; NSApp.mainMenu = menu
        window.title = "Shell Command Hub"; window.minSize = NSSize(width: 900, height: 620)
        window.delegate = self; window.isReleasedWhenClosed = false
        tool = min(2, max(0, defaults.integer(forKey: "selectedTool")))
        mediaDirectory = defaults.string(forKey: "mediaDirectory") ?? NSHomeDirectory()
        archiveDirectory = defaults.string(forKey: "archiveDirectory") ?? NSHomeDirectory()
        portQuery = defaults.string(forKey: "portQuery") ?? ""
        mediaInput.stringValue = mediaDirectory; archiveInput.stringValue = archiveDirectory; portInput.stringValue = portQuery
        recursive.state = defaults.bool(forKey: "recursive") ? .on : .off
        proto.selectedSegment = defaults.bool(forKey: "udp") ? 1 : 0
        buildShell(); buildMediaPage(); buildArchivePage(); buildPortsPage()
        [mediaPage, archivePage, portsPage].enumerated().forEach { $0.element.isHidden = $0.offset != tool }
        sidebar.selectRowIndexes(IndexSet(integer: tool), byExtendingSelection: false)
        if let saved = defaults.string(forKey: "windowFrame") {
            let frame = NSRectFromString(saved)
            if frame.width.isFinite && frame.height.isFinite && frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width >= window.minSize.width && frame.height >= window.minSize.height {
                let screen = NSScreen.screens.max { a, b in a.visibleFrame.intersection(frame).size.area < b.visibleFrame.intersection(frame).size.area } ?? NSScreen.main!
                let bounds = screen.visibleFrame
                let size = NSSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
                window.setFrame(NSRect(x: max(bounds.minX, min(frame.minX, bounds.maxX - size.width)), y: max(bounds.minY, min(frame.minY, bounds.maxY - size.height)), width: size.width, height: size.height), display: false)
            } else { window.center() }
        } else { window.center() }
        restoring = false
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); loadCurrent()
    }
    func buildShell() {
        let side = NSVisualEffectView(); side.material = .sidebar; side.blendingMode = .behindWindow
        let content = window.contentView!; side.translatesAutoresizingMaskIntoConstraints = false; workspace.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(side); content.addSubview(workspace)
        NSLayoutConstraint.activate([side.leadingAnchor.constraint(equalTo: content.leadingAnchor), side.topAnchor.constraint(equalTo: content.topAnchor), side.bottomAnchor.constraint(equalTo: content.bottomAnchor), side.widthAnchor.constraint(equalToConstant: 174), workspace.leadingAnchor.constraint(equalTo: side.trailingAnchor), workspace.trailingAnchor.constraint(equalTo: content.trailingAnchor), workspace.topAnchor.constraint(equalTo: content.topAnchor), workspace.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        let logo = NSImageView(image: NSApp.applicationIconImage); logo.widthAnchor.constraint(equalToConstant: 32).isActive = true; logo.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let brand = stack([logo, text("Command Hub", size: 14, weight: .semibold)], vertical: false, spacing: 8)
        sidebar.headerView = nil; sidebar.rowHeight = 38; sidebar.style = .sourceList; sidebar.backgroundColor = .clear
        sidebar.delegate = self; sidebar.dataSource = self; sidebar.focusRingType = .none
        sidebar.addTableColumn(NSTableColumn(identifier: .init("navigation")))
        let navigation = NSScrollView(); navigation.drawsBackground = false; navigation.documentView = sidebar
        navigation.heightAnchor.constraint(equalToConstant: 126).isActive = true
        let terminal = NSButton(title: "打开终端 TUI", image: NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!, target: self, action: #selector(openTerminal)); terminal.bezelStyle = .recessed
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .vertical)
        let contents = stack([brand, navigation, spacer, terminal, text("关闭窗口后应用仍在运行", size: 11, color: .secondaryLabelColor)], spacing: 18)
        pin(contents, in: side, inset: 14); navigation.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        for page in [mediaPage, archivePage, portsPage] { pin(page, in: workspace) }
    }
    func tableScroll(_ table: NSTableView, columns: [(String, CGFloat)]) -> NSScrollView {
        table.delegate = self; table.dataSource = self; table.rowHeight = 32; table.usesAlternatingRowBackgroundColors = true; table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (index, item) in columns.enumerated() {
            let column = NSTableColumn(identifier: .init(String(index))); column.title = item.0; column.width = item.1; column.minWidth = min(item.1, 70)
            table.addTableColumn(column)
        }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.borderType = .bezelBorder
        return scroll
    }
    func buildMediaPage() {
        mediaInput.placeholderString = "输入媒体目录路径，按回车切换"; mediaInput.target = self; mediaInput.action = #selector(scanMedia)
        mediaInput.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mediaChoose.target = self; mediaChoose.action = #selector(chooseDirectory); mediaChoose.tag = 0
        mediaRefresh.target = self; mediaRefresh.action = #selector(scanMedia)
        recursive.target = self; recursive.action = #selector(scanMedia)
        mediaSearch.placeholderString = "筛选文件名"; mediaSearch.delegate = self
        mediaSearch.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let path = stack([mediaInput, mediaChoose, mediaRefresh], vertical: false)
        let filters = stack([mediaSearch, recursive], vertical: false, spacing: 18)
        mediaSearch.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let files = tableScroll(mediaTable, columns: [("媒体文件", 300), ("格式", 70)])
        mediaTable.rowHeight = 38
        let library = stack([filters, files, mediaCount], spacing: 10)
        filters.widthAnchor.constraint(equalTo: library.widthAnchor).isActive = true; files.widthAnchor.constraint(equalTo: library.widthAnchor).isActive = true
        let details = NSScrollView(); details.hasVerticalScroller = true; details.drawsBackground = false
        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false; details.documentView = document
        document.widthAnchor.constraint(equalTo: details.contentView.widthAnchor).isActive = true
        inspector.orientation = .vertical; inspector.alignment = .leading; inspector.spacing = 10; pin(inspector, in: document, inset: 16)
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(library); split.addArrangedSubview(details)
        library.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        details.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        details.widthAnchor.constraint(lessThanOrEqualToConstant: 390).isActive = true
        details.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.43).isActive = true
        let root = stack([text("媒体信息", size: 24, weight: .semibold), text("浏览音视频文件，查看格式、时长与音轨属性。", color: .secondaryLabelColor), path, split, mediaStatus], spacing: 16)
        pin(root, in: mediaPage, inset: 24)
        for view in [path, split, mediaStatus] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        split.setContentHuggingPriority(.init(1), for: .vertical); showMediaPlaceholder("选择一个媒体文件", message: "文件属性会显示在这里。可直接输入路径切换目录，或开启子目录扫描。")
    }
    func buildArchivePage() {
        archiveInput.placeholderString = "输入需要整理的目录路径，按回车更新计划"; archiveInput.target = self; archiveInput.action = #selector(scanArchive)
        archiveInput.setContentHuggingPriority(.defaultLow, for: .horizontal)
        archiveChoose.target = self; archiveChoose.action = #selector(chooseDirectory); archiveChoose.tag = 1
        archiveRefresh.target = self; archiveRefresh.action = #selector(scanArchive)
        let path = stack([archiveInput, archiveChoose, archiveRefresh], vertical: false)
        let rules = stack([
            stack([symbol("checkmark.circle", description: "成功"), text("成功解压后删除原包；失败或目标已存在时保留原包。")], vertical: false),
            stack([symbol("folder", description: "处理范围"), text("扫描两层 ZIP，同时清理包装目录并整理文件夹名称。")], vertical: false)
        ], spacing: 8)
        rules.setContentHuggingPriority(.required, for: .vertical)
        let plan = tableScroll(archiveTable, columns: [("待处理压缩包", 240), ("预计解压位置", 400)])
        let planPane = stack([archiveCount, plan], spacing: 10); plan.widthAnchor.constraint(equalTo: planPane.widthAnchor).isActive = true
        archiveLog.isEditable = false; archiveLog.isSelectable = true; archiveLog.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        archiveLog.textContainerInset = NSSize(width: 12, height: 12); archiveLog.isHorizontallyResizable = false; archiveLog.isVerticallyResizable = true
        archiveLog.autoresizingMask = [.width]; archiveLog.textContainer?.widthTracksTextView = true
        archiveLog.string = "准备就绪。先查看处理计划，再点击“开始整理”。没有 ZIP 时也可以整理已有目录。"
        let log = NSScrollView(); log.hasVerticalScroller = true; log.borderType = .bezelBorder; log.documentView = archiveLog
        let logPane = stack([text("执行记录", size: 14, weight: .semibold), log], spacing: 10); log.widthAnchor.constraint(equalTo: logPane.widthAnchor).isActive = true
        let split = stack([planPane, logPane], spacing: 16)
        planPane.widthAnchor.constraint(equalTo: split.widthAnchor).isActive = true
        logPane.widthAnchor.constraint(equalTo: split.widthAnchor).isActive = true
        planPane.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true; logPane.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        planPane.heightAnchor.constraint(equalTo: logPane.heightAnchor).isActive = true
        archiveProgress.style = .bar; archiveProgress.isIndeterminate = false; archiveProgress.minValue = 0; archiveProgress.maxValue = 1
        archiveAction.target = self; archiveAction.action = #selector(runArchive); archiveAction.bezelStyle = .rounded; archiveAction.hasDestructiveAction = true
        archiveCancel.target = self; archiveCancel.action = #selector(cancelTask); archiveCancel.isEnabled = false
        let buttons = stack([archiveStatus, archiveCancel, archiveAction], vertical: false, spacing: 14)
        archiveStatus.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let root = stack([text("解压整理", size: 24, weight: .semibold), text("先核对处理计划，再执行整个目录。", color: .secondaryLabelColor), path, rules, split, archiveProgress, buttons], spacing: 16)
        pin(root, in: archivePage, inset: 24)
        for view in [path, split, archiveProgress, buttons] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        split.setContentHuggingPriority(.init(1), for: .vertical)
    }
    func buildPortsPage() {
        portInput.placeholderString = "精确端口，留空查询全部"; portInput.target = self; portInput.action = #selector(scanPorts)
        portInput.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true; portInput.setContentHuggingPriority(.defaultLow, for: .horizontal)
        proto.target = self; proto.action = #selector(scanPorts)
        portRefresh.target = self; portRefresh.action = #selector(scanPorts)
        let search = stack([portInput, portRefresh, proto], vertical: false, spacing: 12)
        let table = tableScroll(portTable, columns: [("端口", 65), ("进程", 160), ("PID", 75), ("用户", 85), ("本地地址", 250)])
        let fieldNames = ["进程", "启动时间", "父进程", "工作目录"]
        let grid = NSGridView(views: fieldNames.map { name in
            let value = text("—"); value.isSelectable = true; portValues[name] = value
            return [text(name, size: 12, color: .secondaryLabelColor), value]
        })
        grid.columnSpacing = 18; grid.rowSpacing = 10; grid.column(at: 0).width = 64
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 1).xPlacement = .fill
        portAction.target = self; portAction.action = #selector(stopSelectedPort); portAction.isEnabled = false; portAction.hasDestructiveAction = true
        let actions = stack([portStatus, portAction], vertical: false, spacing: 16); portStatus.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let separator = NSBox(); separator.boxType = .separator
        let root = stack([text("端口管理", size: 24, weight: .semibold), text("按本地端口定位占用，核对进程来源后安全终止。", color: .secondaryLabelColor), search, portCount, table, separator, text("进程信息", size: 14, weight: .semibold), grid, actions], spacing: 14)
        pin(root, in: portsPage, inset: 24)
        for view in [search, table, separator, grid, actions] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        table.setContentHuggingPriority(.init(1), for: .vertical)
    }
    func remember() {
        guard !restoring else { return }
        defaults.set(tool, forKey: "selectedTool"); defaults.set(mediaDirectory, forKey: "mediaDirectory"); defaults.set(archiveDirectory, forKey: "archiveDirectory")
        defaults.set(portQuery, forKey: "portQuery"); defaults.set(recursive.state == .on, forKey: "recursive"); defaults.set(proto.selectedSegment == 1, forKey: "udp")
        if !window.isMiniaturized && !window.styleMask.contains(.fullScreen) { defaults.set(NSStringFromRect(window.frame), forKey: "windowFrame") }
    }
    func windowDidMove(_ notification: Notification) { remember() }
    func windowDidResize(_ notification: Notification) { remember() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { remember(); return true }
    @objc func showWindow() { window.deminiaturize(nil); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(); let open = NSMenuItem(title: "打开 Shell Command Hub", action: #selector(showWindow), keyEquivalent: ""); open.target = self; menu.addItem(open); return menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        remember(); guard busy else { return .terminateNow }
        showWindow()
        guard confirm("中断任务并退出？", "未完成 ZIP 会保留，已完成项目不回滚。") else { return .terminateCancel }
        quitting = true; cancelTask(); return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { remember() }
    @objc func chooseDirectory(_ sender: NSButton) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: sender.tag == 0 ? mediaDirectory : archiveDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            if sender.tag == 0 { mediaInput.stringValue = url.path; scanMedia() } else { archiveInput.stringValue = url.path; scanArchive() }
        }
    }
    func setBusy(_ value: Bool) {
        busy = value
        for control in [mediaInput as NSControl, archiveInput, portInput, mediaChoose, archiveChoose, mediaRefresh, archiveRefresh, portRefresh, recursive, mediaSearch, proto, archiveAction] { control.isEnabled = !value }
        archiveCancel.isEnabled = value && archiveRunning
        portAction.isEnabled = !value && ports.indices.contains(portTable.selectedRow)
    }
    func run(_ arguments: [String], executable: String = "/bin/bash", stream: Bool = false, completion: @escaping (Data, Int32) -> Void) {
        guard !busy else { return }
        let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments; p.environment = environment(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { currentStatus.stringValue = error.localizedDescription; archiveRunning = false; return }
        process = p; setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            var output = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData; if chunk.isEmpty { break }; output.append(chunk)
                if stream {
                    let log = String(decoding: output, as: UTF8.self)
                    DispatchQueue.main.async {
                        self.archiveLog.string = log; self.archiveLog.scrollToEndOfDocument(nil)
                        if let line = log.components(separatedBy: "\n").last(where: { $0.hasPrefix("[") && $0.contains("/") }), let end = line.firstIndex(of: "]") {
                            let values = line[line.index(after: line.startIndex)..<end].split(separator: "/").compactMap { Int($0) }
                            if values.count == 2 { self.archiveProgress.maxValue = Double(max(1, values[1])); self.archiveProgress.doubleValue = Double(max(0, values[0] - 1)); self.archiveStatus.stringValue = "正在处理 \(values[0]) / \(values[1])" }
                        }
                    }
                }
            }
            p.waitUntilExit(); let result = output
            DispatchQueue.main.async {
                self.process = nil; self.archiveRunning = false; self.setBusy(false); completion(result, p.terminationStatus)
                if self.quitting { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
    }
    func loadCurrent() { if tool == 0 { scanMedia() } else if tool == 1 { scanArchive() } else { scanPorts() } }
    @objc func scanMedia() {
        guard !busy else { return }
        let dir = (mediaInput.stringValue as NSString).expandingTildeInPath; var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { mediaStatus.stringValue = "目录不存在，请重新输入或选择目录。"; return }
        mediaDirectory = URL(fileURLWithPath: dir).standardizedFileURL.path; mediaInput.stringValue = mediaDirectory; remember()
        mediaFiles = []; visibleMedia = []; mediaCache = [:]; mediaTable.reloadData(); mediaStatus.stringValue = "正在扫描媒体文件…"
        run(["-c", "source \"$1\"; media_scan \"$2\" \"$3\"", "_", toolbox.appendingPathComponent("tools/media/videoinfo_beauty.sh").path, mediaDirectory, recursive.state == .on ? "1" : "0"]) { data, code in
            guard code == 0 else { self.showMediaPlaceholder("扫描失败", message: String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "\n")); self.mediaStatus.stringValue = "请检查目录权限，或切换其他目录。"; return }
            self.mediaFiles = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }; self.filterMedia()
            self.mediaStatus.stringValue = self.mediaFiles.isEmpty ? "此目录没有媒体文件，可更换目录或包含子目录。" : "选择文件即可查看属性 · 支持常见音视频格式"
            self.showMediaPlaceholder("选择一个媒体文件", message: "格式、视频和音轨属性会按所选文件显示。")
        }
    }
    func filterMedia() {
        let query = mediaSearch.stringValue
        visibleMedia = mediaFiles.filter { query.isEmpty || ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(query) }
        mediaTable.reloadData(); mediaCount.stringValue = "\(visibleMedia.count) 个文件" + (query.isEmpty ? "" : " · 共 \(mediaFiles.count) 个")
        showMediaPlaceholder("选择一个媒体文件", message: "格式、视频和音轨属性会按所选文件显示。")
    }
    func controlTextDidChange(_ notification: Notification) { if (notification.object as? NSSearchField) === mediaSearch { filterMedia() } }
    func showMediaPlaceholder(_ title: String, message: String) {
        inspector.arrangedSubviews.forEach { inspector.removeArrangedSubview($0); $0.removeFromSuperview() }
        inspector.addArrangedSubview(symbol("doc.text.magnifyingglass", description: "文件属性", size: 30))
        inspector.addArrangedSubview(text(title, size: 16, weight: .semibold)); inspector.addArrangedSubview(text(message, color: .secondaryLabelColor))
        for view in inspector.arrangedSubviews { view.widthAnchor.constraint(lessThanOrEqualTo: inspector.widthAnchor).isActive = true }
    }
    func showMediaInfo(_ data: Data, file: String, code: Int32) {
        guard code == 0 else { showMediaPlaceholder("无法读取媒体属性", message: String(decoding: data, as: UTF8.self)); return }
        inspector.arrangedSubviews.forEach { inspector.removeArrangedSubview($0); $0.removeFromSuperview() }
        inspector.addArrangedSubview(text((file as NSString).lastPathComponent, size: 17, weight: .semibold))
        let path = text(file, size: 11, color: .secondaryLabelColor); path.isSelectable = true; inspector.addArrangedSubview(path)
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
            if line.hasPrefix("│ [") {
                let divider = NSBox(); divider.boxType = .separator; inspector.addArrangedSubview(divider); divider.widthAnchor.constraint(equalTo: inspector.widthAnchor).isActive = true
                let title = line.contains("General") ? "概览" : line.contains("Video") ? "视频" : line.contains("Audio") ? "音频" : line.replacingOccurrences(of: "│ ", with: "")
                inspector.addArrangedSubview(text(title, size: 13, weight: .semibold))
            } else if line.hasPrefix("│ "), let separator = line.range(of: "：") {
                let key = String(line.dropFirst(2)[..<separator.lowerBound]); if key == "完整路径" { continue }
                let value = text(String(line[separator.upperBound...]), size: 12); value.isSelectable = true
                let label = text(key, size: 12, color: .secondaryLabelColor); label.widthAnchor.constraint(equalToConstant: 72).isActive = true
                let row = stack([label, value], vertical: false, spacing: 8); row.alignment = .firstBaseline
                inspector.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: inspector.widthAnchor).isActive = true
            }
        }
        for view in inspector.arrangedSubviews { view.widthAnchor.constraint(lessThanOrEqualTo: inspector.widthAnchor).isActive = true }
    }
    @objc func scanArchive() {
        guard !busy else { return }
        let dir = (archiveInput.stringValue as NSString).expandingTildeInPath; var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { archiveStatus.stringValue = "目录不存在，请重新选择。"; return }
        archiveDirectory = URL(fileURLWithPath: dir).standardizedFileURL.path; archiveInput.stringValue = archiveDirectory; remember()
        archives = []; archiveTable.reloadData(); archiveStatus.stringValue = "正在生成处理计划…"
        archiveLog.string = "准备就绪。先查看处理计划，再点击“开始整理”。没有 ZIP 时也可以整理已有目录。"
        archiveProgress.doubleValue = 0; archiveProgress.maxValue = 1
        run([archiveDirectory, "-maxdepth", "2", "-type", "f", "-iname", "*.zip", "-print0"], executable: "/usr/bin/find") { data, code in
            guard code == 0 else { self.archiveLog.string = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "\n"); self.archiveCount.stringValue = "未生成处理计划"; self.archiveStatus.stringValue = "扫描失败，请检查目录权限。"; return }
            self.archives = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }; self.archiveTable.reloadData()
            self.archiveCount.stringValue = "处理计划 · \(self.archives.count) 个 ZIP"
            self.archiveStatus.stringValue = self.archives.isEmpty ? "没有 ZIP，仍可整理已有目录。" : "预览不会修改文件。"
        }
    }
    @objc func runArchive() {
        guard !busy else { return }
        let dir = (archiveInput.stringValue as NSString).expandingTildeInPath; var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { archiveStatus.stringValue = "目录不存在，请重新选择。"; return }
        guard dir == archiveDirectory else { scanArchive(); archiveStatus.stringValue = "目录已更改，请核对新计划后开始整理。"; return }
        guard confirm("开始解压整理？", "目录：\(dir)\n处理整个目录的两层 ZIP，成功后删除原包，并清理包装目录、整理文件夹名称。\n中断保留未完成 ZIP，已完成项目不回滚。") else { return }
        archiveLog.string = ""; archiveStatus.stringValue = "正在准备…"; archiveProgress.doubleValue = 0
        archiveProgress.isIndeterminate = archives.isEmpty; archiveProgress.startAnimation(nil); archiveRunning = true
        run([toolbox.appendingPathComponent("tools/archive/zip-tidy.sh").path, dir], stream: true) { _, code in
            self.archiveProgress.stopAnimation(nil); self.archiveProgress.isIndeterminate = false
            if code == 0 { self.archiveProgress.doubleValue = self.archiveProgress.maxValue }
            self.archiveStatus.stringValue = code == 0 ? "整理完成 · 点击“更新计划”查看目录现状" : code == 143 || code == 130 ? "已中断，未完成 ZIP 已保留。" : "整理结束，存在错误（退出码 \(code)），请查看执行记录。"
        }
    }
    @objc func scanPorts() {
        guard !busy else { return }
        let value = portInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty || (value.utf8.allSatisfy { (48...57).contains($0) } && value.count <= 5 && (1...65535).contains(Int(value) ?? 0)) else { portStatus.stringValue = "端口必须为 1–65535；留空查询全部。"; return }
        portQuery = value.isEmpty ? "" : String(Int(value)!); portInput.stringValue = portQuery; remember()
        ports = []; portTable.reloadData(); portValues.values.forEach { $0.stringValue = "—" }; portAction.isEnabled = false; portCount.stringValue = "正在查询…"; portStatus.stringValue = "仅显示本地监听或绑定，不包含客户端连接。"
        run([toolbox.appendingPathComponent("tools/network/port-info.sh").path, "--snapshot", proto.selectedSegment == 0 ? "TCP" : "UDP", portQuery]) { data, code in
            guard code == 0 else { self.portStatus.stringValue = String(decoding: data, as: UTF8.self); self.portCount.stringValue = "查询失败"; return }
            self.ports = String(decoding: data, as: UTF8.self).split(separator: "\n").map { $0.components(separatedBy: "\t") }.filter { $0.count == 7 }; self.portTable.reloadData()
            self.portCount.stringValue = "\(self.ports.count) 个占用 · 精确端口 \(self.portQuery.isEmpty ? "全部" : self.portQuery)"
            self.portStatus.stringValue = self.ports.isEmpty ? "没有匹配的端口占用。" : "选择进程查看来源；终止前会再次核对身份。"
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === sidebar ? 3 : tableView === mediaTable ? visibleMedia.count : tableView === archiveTable ? archives.count : ports.count }
    func selectionShouldChange(in tableView: NSTableView) -> Bool { !busy }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebar {
            guard names.indices.contains(row) else { return nil }
            return stack([symbol(icons[row], description: names[row]), text(names[row], size: 13, weight: .medium)], vertical: false, spacing: 10)
        }
        let column = Int(tableColumn?.identifier.rawValue ?? "0") ?? 0; var value = ""
        if tableView === mediaTable {
            guard visibleMedia.indices.contains(row) else { return nil }; let file = visibleMedia[row]
            if column == 0 {
                let audio = ["mp3", "wav", "flac", "aac", "ogg", "m4a", "wma"].contains((file as NSString).pathExtension.lowercased())
                let name = text((file as NSString).lastPathComponent); name.lineBreakMode = .byTruncatingMiddle; name.toolTip = file
                return stack([symbol(audio ? "waveform" : "film", description: audio ? "音频" : "视频", size: 16), name], vertical: false)
            }
            value = (file as NSString).pathExtension.uppercased()
        } else if tableView === archiveTable {
            guard archives.indices.contains(row) else { return nil }; let file = archives[row]
            value = column == 0 ? String(file.dropFirst(archiveDirectory.count + 1)) : archiveDirectory + "/" + ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        } else {
            guard ports.indices.contains(row) else { return nil }; let record = ports[row]; let values = [record[2], record[4], record[0], record[3], record[5]]
            guard values.indices.contains(column) else { return nil }; value = values[column]
        }
        let cell = NSTextField(labelWithString: value); cell.lineBreakMode = .byTruncatingMiddle; cell.toolTip = value
        if tableView === portTable && (column == 0 || column == 2) { cell.font = .monospacedDigitSystemFont(ofSize: 13, weight: column == 0 ? .medium : .regular) }
        return stack([cell], vertical: false, spacing: 0)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, !busy else { return }
        if table === sidebar {
            guard !restoring, names.indices.contains(sidebar.selectedRow), tool != sidebar.selectedRow else { return }
            tool = sidebar.selectedRow; [mediaPage, archivePage, portsPage].enumerated().forEach { $0.element.isHidden = $0.offset != tool }; remember(); loadCurrent()
        } else if table === mediaTable, visibleMedia.indices.contains(mediaTable.selectedRow) {
            let file = visibleMedia[mediaTable.selectedRow]
            if let cached = mediaCache[file] { showMediaInfo(cached, file: file, code: 0); mediaStatus.stringValue = "已读取媒体属性"; return }
            mediaStatus.stringValue = "正在读取属性…"
            run(["-c", "source \"$1\"; media_inspect \"$2\"", "_", toolbox.appendingPathComponent("tools/media/videoinfo_beauty.sh").path, file]) { data, code in
                if code == 0 { self.mediaCache[file] = data }; self.showMediaInfo(data, file: file, code: code); self.mediaStatus.stringValue = code == 0 ? "已读取媒体属性" : "无法分析此文件，请选择其他文件。"
            }
        } else if table === portTable, ports.indices.contains(portTable.selectedRow) {
            let row = ports[portTable.selectedRow]; portValues["进程"]?.stringValue = "\(row[4]) · PID \(row[0]) · \(row[3])"; portValues["启动时间"]?.stringValue = row[6]
            portValues["父进程"]?.stringValue = "—"; portValues["工作目录"]?.stringValue = "—"
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hub-detail-\(UUID().uuidString)")
            do { try (row.joined(separator: "\t") + "\n").write(to: file, atomically: true, encoding: .utf8) } catch { portStatus.stringValue = error.localizedDescription; return }
            run([toolbox.appendingPathComponent("tools/network/port-info.sh").path, "--detail", file.path]) { data, _ in
                for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
                    for key in ["父进程", "工作目录"] where line.hasPrefix(key + "：") { self.portValues[key]?.stringValue = String(line.dropFirst(key.count + 1)) }
                }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    func confirm(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "确认执行")
        return alert.runModal() == .alertSecondButtonReturn
    }
    @objc func stopSelectedPort() {
        guard !busy else { return }; guard portInput.stringValue == portQuery else { scanPorts(); return }
        guard ports.indices.contains(portTable.selectedRow) else { return }; stopPort(ports[portTable.selectedRow], signal: "TERM")
    }
    func stopPort(_ row: [String], signal: String) {
        guard confirm("终止 PID \(row[0]) · SIG\(signal)？", "进程：\(row[4])\n端口：\(row[1]) \(row[2])\n地址：\(row[5])\n启动时间：\(row[6])\n将重新核对身份和端口归属，仅终止这个 PID。") else { return }
        portStatus.stringValue = "正在终止所选进程…"
        run([toolbox.appendingPathComponent("tools/network/port-info.sh").path, "--stop", row[0], row[6], row[1], row[2], signal]) { data, code in
            self.portStatus.stringValue = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if code == 4 && signal == "TERM" { self.stopPort(row, signal: "KILL") }
        }
    }
    @objc func cancelTask() { process?.terminate(); currentStatus.stringValue = "正在中断并回收子进程…" }
    @objc func openTerminal() { do { try terminalLaunch() } catch { currentStatus.stringValue = error.localizedDescription } }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: appVersion]) }
    @objc func checkUpdates() {
        guard let address = bundle.object(forInfoDictionaryKey: "HubUpdateURL") as? String, let url = URL(string: address), url.scheme == "https" else {
            let alert = NSAlert(); alert.messageText = "当前版本 \(appVersion)"; alert.informativeText = "尚未配置更新源。安装发布的新版本替换现有应用即可升级，无需开发目录。"; alert.runModal(); return
        }
        currentStatus.stringValue = "正在检查更新…"
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: String], let latest = json["version"], let address = json["downloadURL"], let download = URL(string: address), download.scheme == "https", error == nil else { self.currentStatus.stringValue = "更新源不可用"; return }
                if latest.compare(appVersion, options: .numeric) == .orderedDescending {
                    if self.confirm("发现版本 \(latest)", "\(json["notes"] ?? "")\n将打开发布者的下载页面。下载后退出并替换应用完成升级。") { NSWorkspace.shared.open(download) }
                } else { self.currentStatus.stringValue = "已是最新版本 \(appVersion)" }
            }
        }.resume()
    }
}
extension NSSize { var area: CGFloat { max(0, width) * max(0, height) } }

if bundle.object(forInfoDictionaryKey: "HubInterface") as? String == "tui" {
    do { try terminalLaunch(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let delegate = HubApp(); app.delegate = delegate; app.run()
