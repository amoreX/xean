import Foundation
import Testing

@testable import BlitzClean

struct TemporaryCleanupTests {
  @Test func findsOnlyGeneratedEnvironmentsAndBuildsAndKeepsScratchWork() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("job/venv/pyvenv.cfg", "home = /usr/bin\n")
    try fixture.write("job/venv/bin/python", "fixture")
    try fixture.write("job/venv/lib/package", "fixture")
    try fixture.write("unknown/pyvenv.cfg", "home = /usr/bin\n")
    try fixture.write("unknown/bin/python", "fixture")
    try fixture.write("unknown/lib/package", "fixture")
    try fixture.write("unknown/my-source.py", "keep")
    try fixture.write("build/Build/output", "fixture")
    let metadata = try PropertyListSerialization.data(
      fromPropertyList: ["WorkspacePath": fixture.path + "/source/App.xcodeproj"], format: .xml,
      options: 0)
    try metadata.write(to: URL(fileURLWithPath: fixture.path + "/build/info.plist"))
    try fixture.write("claude-\(getuid())/project/session/scratchpad/source.py", "keep")
    try FileManager.default.createSymbolicLink(
      atPath: fixture.path + "/linked-env", withDestinationPath: fixture.path + "/job/venv")
    let found = TemporaryCleanup.discover(
      roots: [fixture.path], categories: [.packages, .builds, .claude])
    #expect(Set(found.rules.compactMap { $0.1.entryName }) == ["venv", "build"])
    #expect(found.kept.count == 2)
    #expect(found.kept.contains { $0.reason.contains("unsaved work") })
    #expect(TemporaryCleanup.kind(at: fixture.path + "/unknown") == nil)
    #expect(TemporaryCleanup.kind(at: fixture.path + "/linked-env") == nil)
    let rule = try #require(found.rules.first { $0.0 == .packages }?.1)
    let fresh = CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false))
    #expect(fresh.candidates.isEmpty)
    #expect(fresh.notes.contains { $0.contains("24 hours") })
    let old = CacheCleaner.scan(
      .init(rules: [rule], date: Date.now.addingTimeInterval(2 * 86_400), respectsAge: false))
    let candidate = try #require(old.candidates.first)
    #expect(throws: CacheCleanError.recent) {
      try CacheCleaner.delete(candidate, respectsAge: false)
    }
    try fixture.write("job/venv/my-source.py", "keep new work")
    #expect(!rule.accepts(candidate.path))
    #expect(throws: CacheCleanError.outsideRoot) {
      try CacheCleaner.delete(candidate, respectsAge: false)
    }
  }

  @Test func smallItemsAndUnknownSizeProtectionsAreNotReportedAsEmpty() {
    var report = CleanerScan(notes: ["Codex is running; kept."])
    #expect(report.inventorySummary == "Some locations were skipped.")
    report.items = [
      .init(category: .packages, path: "/fixture/cache", bytes: 1_000_000, target: .docker)
    ]
    #expect(report.inventorySummary?.contains("included in Clean") == true)
    report.kept = [.init(category: .codex, path: "/fixture/sessions", reason: "History stays")]
    #expect(report.visibleKept.count == 1)
    #expect(report.visibleItems.isEmpty)
    #expect(!CleanerPreferences().categories.contains(.dockerImages))
  }
}

private struct ScopedNotesDriver: CleanerDriver {
  func scan(_ preferences: CleanerPreferences, automatic: Bool) async -> CleanerScan {
    .init(
      notes: ["Claude is running", "Codex is running"],
      categoryNotes: [.claude: ["Claude is running"], .codex: ["Codex is running"]])
  }
  func remove(_ item: CleanerItem, preferences: CleanerPreferences, automatic: Bool) async throws
    -> CleanupWin
  {
    throw CacheCleanError.unverified
  }
  func availableBytes() async -> UInt64? { 50_000_000_000 }
}

@MainActor
struct CleanerScanNoteTests {
  @Test func categoryNotesStayScopedAndSurviveEmptyCleanup() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let defaults = try #require(UserDefaults(suiteName: "scoped-notes-\(UUID())"))
    let model = CleanerModel(
      defaults: defaults, driver: ScopedNotesDriver(),
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    model.preferences.categories = [.claude, .codex]
    await model.scanNow()
    #expect(model.categoryScans[.claude]?.notes == ["Claude is running"])
    #expect(model.categoryScans[.codex]?.notes == ["Codex is running"])
    await model.cleanSelected()
    #expect(Set(model.cleanup?.notes ?? []) == ["Claude is running", "Codex is running"])
    #expect(model.cleanup?.result?.removed == 0)
  }
}
