
let testApplication = NSApplication.shared
let suite = "io.shellcommandhub.tests.\(UUID().uuidString)"
let testDefaults = UserDefaults(suiteName: suite)!
defer { testDefaults.removePersistentDomain(forName: suite) }
let subject = HubApp(defaults: testDefaults)
subject.buildShell(); subject.buildMediaPage(); subject.buildArchivePage(); subject.buildPortsPage()
subject.restoring = false
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

for index in 0..<12 { subject.recordDirectory("/media/\(index)", page: 0) }
subject.recordDirectory("/media/5", page: 0)
subject.recordDirectory("/archives", page: 1)
let recent = testDefaults.stringArray(forKey: "recentMediaDirectories")!
expect(recent.count == 10 && recent.first == "/media/5" && Set(recent).count == 10, "recent paths must be capped, newest first and deduplicated")
subject.menuNeedsUpdate(subject.mediaRecent.menu!)
expect(subject.mediaRecent.menu!.items.contains { $0.representedObject as? String == "/media/5" }, "recent directory must be available in the menu")
let remove = NSMenuItem(); remove.tag = 0; remove.representedObject = "/media/5"
subject.removeRecent(remove)
expect(!(testDefaults.stringArray(forKey: "recentMediaDirectories")!).contains("/media/5"), "remove one recent directory")
remove.representedObject = nil; subject.removeRecent(remove)
expect(testDefaults.stringArray(forKey: "recentMediaDirectories") == nil, "clear all media history")
expect(testDefaults.stringArray(forKey: "recentArchiveDirectories") == ["/archives"], "history must remain independent between pages")

let fixtures = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hub-view-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtures) }
let file = fixtures.appendingPathComponent("clip.wav")
try Data([1, 2, 3]).write(to: file)
subject.mediaDirectory = fixtures.path; subject.mediaInput.stringValue = fixtures.path
subject.mediaFiles = [file.path]; subject.visibleMedia = [file.path]; subject.mediaSizes = [file.path: 3]
subject.mediaCache[file.path] = Data([1]); subject.mediaSearch.stringValue = "clip"
subject.recordDirectory(fixtures.path, page: 0)
subject.clearCurrent(subject.mediaClear)
expect(subject.mediaDirectory.isEmpty && subject.mediaInput.stringValue.isEmpty && subject.mediaSearch.stringValue.isEmpty, "clear media path and filter")
expect(subject.mediaFiles.isEmpty && subject.visibleMedia.isEmpty && subject.mediaSizes.isEmpty && subject.mediaCache.isEmpty, "clear media rows, metadata and inspector cache")
expect(testDefaults.stringArray(forKey: "recentMediaDirectories") == [fixtures.path], "clearing the current view must preserve history")
expect(FileManager.default.fileExists(atPath: file.path), "clearing the view must not delete files")
subject.archiveDirectory = fixtures.path; subject.archiveInput.stringValue = fixtures.path
subject.archives = ["/test.zip"]; subject.archiveLog.string = "completed"
subject.clearCurrent(subject.archiveClear)
expect(subject.archiveDirectory.isEmpty && subject.archives.isEmpty && subject.archiveLog.string.isEmpty && !subject.archiveAction.isEnabled, "clear plan, log and execution state")
expect(testDefaults.stringArray(forKey: "recentArchiveDirectories") == ["/archives"], "archive clear must preserve recent directories")
subject.busy = true; subject.mediaInput.stringValue = "pending"; subject.clearCurrent(subject.mediaClear)
expect(subject.mediaInput.stringValue == "pending", "do not clear an active task")
subject.busy = false

subject.visibleMedia = ["/clip10.mp4", "/clip2.wav", "/clip1.mp4"]
subject.mediaSizes = ["/clip10.mp4": 20, "/clip2.wav": 100, "/clip1.mp4": 3]
subject.sortMedia()
expect(subject.visibleMedia == ["/clip1.mp4", "/clip2.wav", "/clip10.mp4"], "default media sorting must use natural filename order")
subject.reordering = true; subject.mediaTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false); subject.reordering = false
subject.mediaTable.sortDescriptors = [NSSortDescriptor(key: "2", ascending: false)]
expect(subject.visibleMedia == ["/clip2.wav", "/clip10.mp4", "/clip1.mp4"], "file size must sort by bytes, descending")
expect(subject.mediaTable.selectedRow == 0, "sorting must preserve the selected file")
subject.mediaTable.sortDescriptors = [NSSortDescriptor(key: "2", ascending: true)]
expect(subject.visibleMedia.first == "/clip1.mp4", "clicking again must reverse the sort")
subject.mediaTable.sortDescriptors = [NSSortDescriptor(key: "1", ascending: true)]
expect(subject.visibleMedia.last == "/clip2.wav", "sort media by format")

subject.ports = [["120", "TCP", "443", "user", "process10", "*", "start"], ["9", "TCP", "80", "user", "process2", "*", "start"], ["30", "TCP", "9", "user", "process1", "*", "start"]]
subject.sortPorts()
expect(subject.ports.map { $0[2] } == ["9", "80", "443"], "default port order must be numeric")
subject.reordering = true; subject.portTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false); subject.reordering = false
subject.portTable.sortDescriptors = [NSSortDescriptor(key: "0", ascending: false)]
expect(subject.ports.map { $0[2] } == ["443", "80", "9"] && subject.ports[subject.portTable.selectedRow][0] == "9", "port sorting must preserve process identity")
subject.portTable.sortDescriptors = [NSSortDescriptor(key: "2", ascending: true)]
expect(subject.ports.map { $0[0] } == ["9", "30", "120"], "PID order must be numeric")

for size in [NSSize(width: 900, height: 620), NSSize(width: 1920, height: 1080)] {
    subject.window.setContentSize(size); subject.window.contentView!.layoutSubtreeIfNeeded()
    expect(abs(subject.workspace.frame.maxX - subject.window.contentView!.bounds.maxX) < 1, "workspace must fill the window at \(size)")
    expect(subject.mediaPage.frame.width > 600, "media page must expand with the window")
}
expect(subject.windowShouldClose(subject.window), "red close must close the window")
expect(!subject.applicationShouldTerminateAfterLastWindowClosed(testApplication), "closing the last window must keep the process alive")
expect(subject.applicationShouldTerminate(testApplication) == .terminateNow, "explicit quit must terminate an idle app")
print("PASS: independent recent history, non-destructive clear, natural/numeric sorting, stable selection, responsive layout and close/quit policy")
