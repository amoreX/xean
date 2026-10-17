import Darwin
import Foundation
import Testing

@testable import BlitzClean

struct CleanerInventoryTests {
  @Test func categoryCachesKeepNestedItemsWhileTheRemovalPlanExcludesThem() {
    var report = CleanerScan(items: [
      .init(category: .worktrees, path: "/fixture/checkout", bytes: 100, target: .docker),
      .init(
        category: .dependencies, path: "/fixture/checkout/node_modules", bytes: 80,
        target: .docker),
    ])
    CleanerScanner.consolidate(&report, excludingOverlaps: false)
    #expect(report.items.count == 2)
    CleanerScanner.consolidate(&report)
    #expect(report.items.map(\.path) == ["/fixture/checkout"])
  }

  @Test func hidesSmallAndUnmeasuredEntriesWithoutChangingCleanupCandidates() {
    let sizes: [UInt64] = [49_999_999, 50_000_000, 50_000_001]
    let report = CleanerScan(
      items: sizes.map {
        .init(category: .docker, path: "fixture/\($0)", bytes: $0, target: .docker)
      },
      kept: (sizes.map(Optional.some) + [nil]).enumerated().map { index, bytes in
        .init(category: .dependencies, path: "fixture/\(index)", reason: "In use", bytes: bytes)
      })
    #expect(report.visibleItems.map(\.bytes) == [50_000_000, 50_000_001])
    #expect(report.visibleKept.compactMap(\.bytes) == [50_000_000, 50_000_001])
    #expect(report.items.count == 3)
    #expect(report.kept.count == 4)
  }
}

struct CleanerSymlinkTests {
  @Test func nestedLinksNeverCountOrDeleteTheirDestinations() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/package/bin/tool", "local executable")
    try fixture.write("outside/keep", String(repeating: "x", count: 1_000_000))
    let path = fixture.path + "/cache/package"
    for (name, destination) in [
      ("tool", "bin/tool"), ("workspace", "../../outside"),
      ("missing", "not-installed"), ("cycle", "."),
    ] {
      try FileManager.default.createSymbolicLink(
        atPath: path + "/" + name, withDestinationPath: destination)
    }
    let tree = try CacheCleaner.tree(.init(path: path))
    #expect(tree.bytes < 1_000_000)
    try fixture.write("outside/keep", "external target changed")
    let unchanged = try CacheCleaner.tree(.init(path: path))
    #expect(unchanged == tree)
    let rule = CacheRule(
      title: "Fixture", path: fixture.path + "/cache", recipe: "Rebuild", owners: [], kind: .cache)
    _ = try CacheCleaner.delete(.init(path: path, rule: rule, tree: tree), respectsAge: false)
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(
      try String(contentsOfFile: fixture.path + "/outside/keep", encoding: .utf8)
        == "external target changed")
  }

  @Test func retargetedLinksBlockRemovalAndLinkedRootsRemainProtected() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/package/one", "first")
    try fixture.write("cache/package/two", "second")
    let path = fixture.path + "/cache/package"
    let link = path + "/tool"
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "one")
    let tree = try CacheCleaner.tree(.init(path: path))
    try FileManager.default.removeItem(atPath: link)
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "two")
    let rule = CacheRule(
      title: "Fixture", path: fixture.path + "/cache", recipe: "Rebuild", owners: [], kind: .cache)
    #expect(throws: CacheCleanError.changed) {
      try CacheCleaner.delete(.init(path: path, rule: rule, tree: tree), respectsAge: false)
    }
    #expect(throws: CacheCleanError.linkedRoot) {
      try CacheCleaner.tree(.init(path: link))
    }
    #expect(FileManager.default.fileExists(atPath: path + "/two"))
  }

  @Test func specialFilesHaveAnAccurateBlocker() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    #expect(mkfifo(fixture.path + "/pipe", 0o600) == 0)
    #expect(throws: CacheCleanError.specialFile) {
      try CacheCleaner.tree(.init(path: fixture.path))
    }
  }

  @Test func manualDependenciesAllowPackageLinksAndKeepAutomaticAgeChecks() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("project/package.json", "{}")
    try fixture.write("project/package-lock.json", "{}")
    try fixture.write("project/node_modules/tool/bin/run", "executable")
    try fixture.write("project/node_modules/.bin/placeholder", "")
    try fixture.write("shared/keep", "shared dependency")
    let path = fixture.path + "/project/node_modules"
    try FileManager.default.createSymbolicLink(
      atPath: path + "/.bin/tool", withDestinationPath: "../tool/bin/run")
    try FileManager.default.createSymbolicLink(
      atPath: path + "/shared", withDestinationPath: "../../shared")
    var preferences = CleanerPreferences()
    preferences.categories = [.dependencies]
    var manual = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path + "/project"], preferences: preferences, automatic: false,
      result: &manual)
    let item = try #require(manual.items.first { $0.path == path })
    #expect(manual.kept.isEmpty)
    var automatic = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path + "/project"], preferences: preferences, automatic: true,
      result: &automatic)
    #expect(automatic.items.isEmpty)
    #expect(automatic.kept.first?.bytes != nil)
    await #expect(throws: CacheCleanError.recent) {
      try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: true)
    }
    _ = try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: false)
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(FileManager.default.fileExists(atPath: fixture.path + "/shared/keep"))
    #expect(FileManager.default.fileExists(atPath: fixture.path + "/project/package-lock.json"))
  }
}
