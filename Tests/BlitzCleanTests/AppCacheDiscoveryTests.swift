import Foundation
import Testing

@testable import BlitzClean

struct AppCacheDiscoveryTests {
  func makeApp(
    _ fixture: CleanerFixture, name: String = "Example", identifier: String = "org.example.app"
  ) throws -> AppCacheDiscovery.App {
    let path = fixture.path + "/Applications/" + name + ".app"
    try fixture.write("Applications/" + name + ".app/Contents/placeholder", "")
    let data = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": identifier, "CFBundleExecutable": name, "CFBundleName": name,
      ], format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
    return try #require(AppCacheDiscovery.app(at: path))
  }

  @Test func discoversConventionsWithoutTouchingProfilesOrUnknownFolders() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let app = try makeApp(fixture)
    for path in [
      "Library/Caches/org.example.app/item",
      "Library/Caches/@exampledesktop-updater/pending/archive", "Library/Caches/unknown/personal",
      "Library/Application Support/Example/Cache/item",
      "Library/Application Support/Example/Local Storage/keep",
    ] {
      try fixture.write(path, "fixture")
    }
    let report = AppCacheDiscovery.discover(home: fixture.path, apps: [app], excluding: [])
    #expect(report.rules.count == 3)
    #expect(report.rules.allSatisfy { $0.kind.alwaysRequiresAge && $0.kind.minimumAgeDays == 7 })
    #expect(
      !report.rules.contains { $0.path.contains("Local Storage") || $0.path.contains("unknown") })
    #expect(report.notes.contains { $0.contains("unknown") })
    let scan = CacheCleaner.scan(.init(rules: report.rules, date: .now, respectsAge: false))
    #expect(scan.candidates.isEmpty)
    #expect(scan.notes.contains { $0.contains("168 hours") })
  }

  @Test func ambiguousOwnersAndSpecializedCachesRemainExcluded() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let first = try makeApp(fixture)
    let second = AppCacheDiscovery.App(
      path: fixture.path + "/other.app", identifier: first.identifier, executable: first.executable,
      names: first.names)
    #expect(AppCacheDiscovery.owner(name: first.identifier, apps: [first, second]) == nil)
    try fixture.write("Library/Caches/org.example.app/protected", "fixture")
    let report = AppCacheDiscovery.discover(
      home: fixture.path, apps: [first],
      excluding: [fixture.path + "/Library/Caches/org.example.app/protected"])
    #expect(report.rules.isEmpty)
  }

  @Test func linkedRootsAndMissingOwnersAreRejected() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let app = try makeApp(fixture)
    try fixture.write("Library/Caches/placeholder", "")
    try fixture.write("documents/keep", "personal")
    try FileManager.default.createSymbolicLink(
      atPath: fixture.path + "/Library/Caches/org.example.app",
      withDestinationPath: fixture.path + "/documents")
    #expect(
      AppCacheDiscovery.discover(home: fixture.path, apps: [app], excluding: []).rules.isEmpty)
    let rule = CacheRule(
      title: "Fixture", path: fixture.path, recipe: "", owners: ["Example"],
      kind: .discoveredAppCache, owningApp: fixture.path + "/missing.app")
    #expect(throws: CacheCleanError.unverified) { try AppCacheDiscovery.validate(rule) }
  }
}
