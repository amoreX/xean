import Foundation
import Testing

@testable import BlitzClean

struct CleanerExpandedCoverageTests {
  @Test func auditedCacheLocationsAreCoveredWithoutProfilesOrMessages() throws {
    let home = "/Users/fixture"
    let apps = CleanerCatalog.rules(.appCaches, home: home)
    #expect(apps.contains { $0.path.hasSuffix("/Slack/Service Worker/CacheStorage") })
    #expect(apps.contains { $0.path.hasSuffix("/Linear/Code Cache") })
    let whatsapp = try #require(apps.first { $0.title == "WhatsApp updater cache" })
    #expect(whatsapp.path.hasSuffix("org.sparkle-project.Sparkle/Installation"))
    #expect(whatsapp.owners.contains("WhatsApp") && whatsapp.owners.contains("Updater"))
    #expect(whatsapp.kind.alwaysRequiresAge && whatsapp.checksRootActivity)
    let zen = try #require(
      CleanerCatalog.rules(.browsers, home: home).first { $0.title == "Zen updater cache" })
    #expect(zen.path.hasSuffix("Mozilla/updates/Applications/Zen"))
    #expect(zen.owners.contains("updater") && zen.checksRootActivity)
    #expect(
      !apps.contains {
        $0.path.contains("Group Containers") || $0.path.hasSuffix("Application Support/Slack")
      })
    let browser = try #require(
      CleanerCatalog.rules(.packages, home: home).first { $0.kind == .browserDownload })
    #expect(browser.accepts(browser.path + "/chromium-1243"))
    #expect(browser.accepts(browser.path + "/chromium_headless_shell-1248"))
    #expect(!browser.accepts(browser.path + "/.links"))
    #expect(!browser.accepts(browser.path + "/chromium-personal"))
    #expect(CleanerCatalog.roots(home: home).contains(home + "/Downloads"))
    #expect(CleanerCatalog.roots(home: home).contains(home + "/.local/share"))
    #expect(!CleanerPreferences().categories.contains(.pythonEnvironments))
  }

  @Test func xcodeTestResultsAreGeneratedButExtraSourceStillBlocksCleanup() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("build/Build/output", "fixture")
    try fixture.write("build/TestResults/test.xcresult/Info.plist", "fixture")
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["WorkspacePath": fixture.path + "/source/App.xcodeproj"], format: .xml,
      options: 0)
    try data.write(to: URL(fileURLWithPath: fixture.path + "/build/info.plist"))
    #expect(TemporaryCleanup.kind(at: fixture.path + "/build") == .temporaryBuild)
    try fixture.write("build/notes.txt", "keep my work")
    #expect(TemporaryCleanup.kind(at: fixture.path + "/build") == nil)
  }

  @Test func pythonEnvironmentsRequireManifestAgeAndRevalidation() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try makeEnvironment(fixture)
    let path = fixture.path + "/project/.venv"
    let rule = PythonEnvironmentCleanup.rule(path)
    #expect(!rule.accepts(path))
    try fixture.write("project/requirements.txt", "example==1.0\n")
    #expect(rule.accepts(path))
    let fresh = CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false))
    #expect(fresh.candidates.isEmpty)
    #expect(fresh.notes.contains { $0.contains("168 hours") })
    let future = CacheCleaner.scan(
      .init(rules: [rule], date: .now.addingTimeInterval(8 * 86_400), respectsAge: false))
    let candidate = try #require(future.candidates.first)
    #expect(throws: CacheCleanError.recent) {
      try CacheCleaner.delete(candidate, respectsAge: false)
    }
    try fixture.write("project/.venv/unsaved.py", "keep")
    #expect(!rule.accepts(path))
    #expect(throws: CacheCleanError.outsideRoot) {
      try CacheCleaner.delete(candidate, respectsAge: false)
    }
  }

  @Test func discoveryFindsEnvironmentsWithoutTraversingPackagesAndKeepsUnverifiedOnes() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try makeEnvironment(fixture)
    try fixture.write("project/.venv/lib/package/package.json", "{}")
    let discovery = DeveloperArtifactScanner.discover(.init(roots: [fixture.path]))
    #expect(discovery.pythonEnvironments == [fixture.path + "/project/.venv"])
    #expect(discovery.projects.isEmpty)
    var preferences = CleanerPreferences()
    preferences.categories = [.pythonEnvironments]
    var scan = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path], preferences: preferences, automatic: false, result: &scan)
    #expect(scan.items.isEmpty)
    #expect(
      scan.kept.contains { $0.category == .pythonEnvironments && $0.reason.contains("manifest") })
  }

  @Test func activeProjectBlocksEnvironmentCleanup() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try makeEnvironment(fixture)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    process.currentDirectoryURL = URL(fileURLWithPath: fixture.path + "/project")
    try process.run()
    defer {
      process.terminate()
      process.waitUntilExit()
    }
    #expect(throws: CacheCleanError.busy) {
      try PythonEnvironmentCleanup.validateActivity(fixture.path + "/project/.venv")
    }
  }

  @Test func trackedPythonFilesAreProtectedEvenInsideAnIgnoredEnvironment() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try makeEnvironment(fixture)
    try fixture.write(".gitignore", ".venv/\n")
    #expect(
      DeveloperCommand.git(.init(directory: fixture.path, arguments: ["init", "-q"])).status == 0)
    let path = fixture.path + "/project/.venv"
    try PythonEnvironmentCleanup.validateActivity(path)
    #expect(
      DeveloperCommand.git(
        .init(directory: fixture.path, arguments: ["add", "-f", "project/.venv/lib/example"])
      ).status == 0)
    #expect(throws: CleanerError.self) { try PythonEnvironmentCleanup.validateActivity(path) }
  }

  private func makeEnvironment(_ fixture: CleanerFixture) throws {
    try fixture.write("project/.venv/pyvenv.cfg", "home = /usr/bin\n")
    try fixture.write("project/.venv/bin/python", "fixture")
    try fixture.write("project/.venv/lib/example", "fixture")
  }
}
