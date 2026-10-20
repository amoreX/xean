import Foundation
import Testing

@testable import BlitzClean

struct CleanerCoverageTests {
  @Test func recognizesPackageManagersHostedByGenericInterpreters() {
    #expect(
      CacheCleaner.runtimeTools("/opt/bin/node /opt/lib/npm/bin/npm-cli.js install") == ["npm"])
    #expect(CacheCleaner.runtimeTools("/opt/bin/python3.13 -m pip install example") == ["pip"])
    #expect(CacheCleaner.runtimeTools("/opt/bin/python3 -m uv sync") == ["uv"])
    #expect(CacheCleaner.runtimeTools("/opt/bin/node /project/server.js").isEmpty)
    #expect(CacheCleaner.runtimeTools("/opt/bin/python3 /project/service.py").isEmpty)
  }

  @Test func catalogKeepsNamedToolsButScopesGenericRuntimesToCacheActivity() throws {
    let home = "/Users/fixture"
    let packages = CleanerCatalog.rules(.packages, home: home)
    let uv = try #require(packages.first { $0.path.hasSuffix("/.cache/uv") })
    #expect(uv.owners == ["uv", "uvx"])
    #expect(uv.checksRootActivity)
    let npm = try #require(packages.first { $0.path.hasSuffix("/.npm/_cacache") })
    #expect(npm.owners.contains("npm"))
    #expect(!npm.owners.contains("node"))
    #expect(npm.checksRootActivity)
    let zen = try #require(
      CleanerCatalog.rules(.browsers, home: home).first {
        $0.path == home + "/Library/Caches/zen"
      })
    #expect(zen.owners.contains("zen"))
    #expect(zen.checksRootActivity)
    #expect(
      CleanerCatalog.rules(.editors, home: home).contains {
        $0.path == home + "/Library/Caches/fed10" && $0.checksRootActivity
      })
  }

  @Test func staleFixturesRequireExactDirectoryNameAndAgeEvenWhenManual() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    for name in ["tickle-desktop-test-Ab12cD", "tickle-desktop-test-recent", "keep-Ab12cD"] {
      try fixture.write(name + "/payload", String(repeating: "x", count: 4096))
    }
    try fixture.write("tickle-desktop-test-file12", "not a directory")
    try FileManager.default.createSymbolicLink(
      atPath: fixture.path + "/tickle-desktop-test-link12",
      withDestinationPath: fixture.path + "/tickle-desktop-test-Ab12cD")
    let rule = CleanerCatalog.staleTestRule(root: fixture.path)
    let target = fixture.path + "/tickle-desktop-test-Ab12cD"
    #expect(rule.accepts(target))
    #expect(!rule.accepts(fixture.path + "/keep-Ab12cD"))
    #expect(!rule.accepts(fixture.path + "/tickle-desktop-test-file12"))
    #expect(!rule.accepts(fixture.path + "/tickle-desktop-test-link12"))
    #expect(
      CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false)).candidates.isEmpty)
    let fresh = CacheCandidate(
      path: target, rule: rule, tree: try CacheCleaner.tree(.init(path: target)))
    #expect(throws: CacheCleanError.recent) { try CacheCleaner.delete(fresh, respectsAge: false) }
    for path in [target + "/payload", target] {
      try FileManager.default.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-2 * 86_400)], ofItemAtPath: path)
    }
    let scan = CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false))
    #expect(scan.candidates.map(\.path) == [target])
    let candidate = try #require(scan.candidates.first)
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: target + "/payload"))
    #expect(throws: CacheCleanError.self) { try CacheCleaner.delete(candidate, respectsAge: false) }
    try handle.close()
    try fixture.write("tickle-desktop-test-Ab12cD/payload", "changed")
    #expect(throws: CacheCleanError.changed) {
      try CacheCleaner.delete(candidate, respectsAge: false)
    }
    #expect(FileManager.default.fileExists(atPath: target))
  }

  @Test func cacheActivityUsesWorkingDirectoryAndStillKeepsNamedTools() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/entry", String(repeating: "x", count: 4096))
    let root = fixture.path + "/cache"
    let rule = CacheRule(
      title: "Fixture", path: root, recipe: "Rebuild", owners: [],
      kind: .cache, checksRootActivity: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["60"]
    process.currentDirectoryURL = URL(fileURLWithPath: root)
    try process.run()
    defer {
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }
    }
    #expect(
      CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false)).candidates.isEmpty)
    process.terminate()
    process.waitUntilExit()
    let unrelated = Process()
    unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
    unrelated.arguments = ["60"]
    unrelated.currentDirectoryURL = URL(fileURLWithPath: fixture.path)
    try unrelated.run()
    defer {
      unrelated.terminate()
      unrelated.waitUntilExit()
    }
    #expect(
      CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false)).candidates.count == 1)
    let namedRule = CacheRule(
      title: "Fixture", path: root, recipe: "Rebuild", owners: ["sleep"],
      kind: .cache, checksRootActivity: true)
    #expect(
      CacheCleaner.scan(.init(rules: [namedRule], date: .now, respectsAge: false)).candidates
        .isEmpty)
  }

  @Test func sharedCacheChecksSiblingActivityBeforeScanAndDeletion() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/entry", String(repeating: "x", count: 4096))
    try fixture.write("cache/other", String(repeating: "y", count: 4096))
    let rule = CacheRule(
      title: "Fixture", path: fixture.path + "/cache", recipe: "Rebuild", owners: [],
      kind: .cache, checksRootActivity: true)
    let scan = CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false))
    let candidate = try #require(scan.candidates.first { $0.name == "entry" })
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: fixture.path + "/cache/other"))
    let activeScan = CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false))
    #expect(activeScan.candidates.isEmpty)
    #expect(!activeScan.notes.isEmpty)
    #expect(throws: CacheCleanError.self) { try CacheCleaner.delete(candidate, respectsAge: false) }
    try handle.close()
    #expect(
      CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false)).candidates.count == 2)
  }
}
