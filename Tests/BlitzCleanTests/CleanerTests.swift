import Foundation
import Testing

@testable import BlitzClean

struct CleanerPolicyTests {
  @Test func projectBuildDeletionIgnoresUnrelatedToolsButKeepsActiveProjects() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("project/package.json", "{}")
    try fixture.write("project/.gitignore", ".next/\n")
    try fixture.write("project/.next/cache", String(repeating: "x", count: 4096))
    try fixture.write("other/keep", "unrelated project")
    let project = fixture.path + "/project"
    try fixture.git(["-C", project, "init", "-b", "main"])
    let unrelated = Process()
    unrelated.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    unrelated.arguments = ["clang", "-x", "c", "-fsyntax-only", "-"]
    let input = Pipe()
    unrelated.standardInput = input
    unrelated.currentDirectoryURL = URL(fileURLWithPath: fixture.path + "/other")
    try unrelated.run()
    defer {
      try? input.fileHandleForWriting.close()
      unrelated.waitUntilExit()
    }
    for _ in 0..<50 {
      if try CacheCleaner.processes().contains("clang") { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(unrelated.isRunning)
    #expect(try CacheCleaner.processes().contains("clang"))
    var preferences = CleanerPreferences()
    preferences.categories = [.builds]
    var scan = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [project], preferences: preferences, automatic: false, result: &scan)
    let item = try #require(scan.items.first { $0.path == project + "/.next" })
    let active = Process()
    active.executableURL = URL(fileURLWithPath: "/bin/sleep")
    active.arguments = ["60"]
    active.currentDirectoryURL = URL(fileURLWithPath: project)
    try active.run()
    defer {
      if active.isRunning {
        active.terminate()
        active.waitUntilExit()
      }
    }
    await #expect(throws: CacheCleanError.busy) {
      try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: false)
    }
    #expect(FileManager.default.fileExists(atPath: item.path))
    active.terminate()
    active.waitUntilExit()
    _ = try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: false)
    #expect(!FileManager.default.fileExists(atPath: item.path))
    #expect(FileManager.default.fileExists(atPath: project + "/package.json"))
    #expect(unrelated.isRunning)
  }

  @Test func worktreeInventoryListsProtectedCheckoutsAndAllowsIndividualYoungWorktrees()
    async throws
  {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.git(["init", "-b", "main"])
    try fixture.git(["config", "user.name", "Fixture"])
    try fixture.git(["config", "user.email", "fixture@example.invalid"])
    try fixture.git(["config", "commit.gpgsign", "false"])
    try fixture.write("source.txt", "tracked")
    try fixture.git(["add", "source.txt"])
    try fixture.git(["commit", "-m", "fixture"])
    let young = fixture.path + "/young"
    let dirty = fixture.path + "/dirty"
    try fixture.git(["worktree", "add", "-b", "young", young])
    try fixture.git(["worktree", "add", "-b", "dirty", dirty])
    try fixture.write("dirty/local.txt", "keep this")
    var preferences = CleanerPreferences()
    preferences.categories = [.worktrees]
    var manual = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path], preferences: preferences, automatic: false, result: &manual)
    #expect(manual.items.map(\.path) == [young])
    #expect(Set(manual.kept.map(\.path)) == [fixture.path, dirty])
    #expect(manual.items.first?.branch == "young")
    var automatic = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path], preferences: preferences, automatic: true, result: &automatic)
    #expect(automatic.items.isEmpty)
    #expect(automatic.kept.contains { $0.path == young })
    let item = try #require(manual.items.first)
    await #expect(throws: CacheCleanError.recent) {
      try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: true)
    }
    _ = try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: false)
    #expect(!FileManager.default.fileExists(atPath: young))
    #expect(FileManager.default.fileExists(atPath: dirty + "/local.txt"))
    #expect(FileManager.default.fileExists(atPath: fixture.path + "/source.txt"))
    try fixture.git(["show-ref", "--verify", "refs/heads/young"])
  }

  @Test func manualCleanupIncludesFreshCachesAndBuildsButStillRejectsChangedFiles() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("package.json", "{}")
    try fixture.write(".gitignore", "dist/\n")
    try fixture.write("dist/output", String(repeating: "x", count: 4096))
    try fixture.write("cache/recent", String(repeating: "x", count: 4096))
    try fixture.git(["init", "-b", "main"])
    let rule = CacheRule(
      title: "Fixture", path: fixture.path + "/cache", recipe: "Rebuild", owners: [], kind: .cache)
    #expect(CacheCleaner.scan(.init(rules: [rule], date: .now)).candidates.isEmpty)
    let scan = CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false))
    let candidate = try #require(scan.candidates.first)
    let item = CleanerItem(
      category: .claude, path: candidate.path, bytes: candidate.tree.bytes,
      target: .cache(candidate))
    try fixture.write("cache/recent", "changed since scan")
    await #expect(throws: CacheCleanError.changed) {
      try await NativeCleanerDriver().remove(item, preferences: .init(), automatic: false)
    }
    let fresh = try #require(
      CacheCleaner.scan(.init(rules: [rule], date: .now, respectsAge: false)).candidates.first)
    _ = try await NativeCleanerDriver().remove(
      .init(category: .claude, path: fresh.path, bytes: fresh.tree.bytes, target: .cache(fresh)),
      preferences: .init(), automatic: false)
    #expect(!FileManager.default.fileExists(atPath: fresh.path))
    let buildRule = CacheRule(
      title: "Build", path: fixture.path, recipe: "Rebuild", owners: [], kind: .cache)
    let path = fixture.path + "/dist"
    let tree = try CacheCleaner.tree(.init(path: path))
    let build = CleanerItem(
      category: .builds, path: path, bytes: tree.bytes,
      target: .build(.init(path: path, rule: buildRule, tree: tree), project: fixture.path))
    await #expect(throws: CacheCleanError.recent) {
      try await NativeCleanerDriver().remove(build, preferences: .init(), automatic: true)
    }
    _ = try await NativeCleanerDriver().remove(build, preferences: .init(), automatic: false)
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test func oneDayOldCachesAreEligibleButNewerFilesStay() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/old", String(repeating: "x", count: 4096))
    try fixture.write("cache/recent", String(repeating: "x", count: 4096))
    let now = Date.now
    let old = fixture.path + "/cache/old"
    let recent = fixture.path + "/cache/recent"
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-86_460)], ofItemAtPath: old)
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-23 * 3_600)], ofItemAtPath: recent)
    let rule = CacheRule(
      title: "Fixture", path: fixture.path + "/cache", recipe: "Rebuild", owners: [], kind: .cache)
    let scan = CacheCleaner.scan(.init(rules: [rule], date: now))
    #expect(scan.candidates.map(\.path) == [old])
    let candidate = try #require(scan.candidates.first)
    let item = CleanerItem(
      category: .claude, path: old, bytes: candidate.tree.bytes, target: .cache(candidate))
    _ = try await NativeCleanerDriver().remove(item, preferences: .init())
    #expect(!FileManager.default.fileExists(atPath: old))
    let recentTree = try CacheCleaner.tree(.init(path: recent))
    #expect(throws: CacheCleanError.recent) {
      try CacheCleaner.delete(.init(path: recent, rule: rule, tree: recentTree))
    }
    #expect(FileManager.default.fileExists(atPath: recent))
  }

  @Test func projectBuildAgeUsesTheSameOneDayCutoff() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("dist/output", "generated")
    let path = fixture.path + "/dist"
    let tree = try CacheCleaner.tree(.init(path: path))
    let now = Date.now
    try CleanerProjectSafety.validateAge(
      path: path, tree: tree, days: CleanupDataKind.cache.minimumAgeDays, worktree: false,
      now: now.addingTimeInterval(86_460))
    #expect(throws: CacheCleanError.recent) {
      try CleanerProjectSafety.validateAge(
        path: path, tree: tree, days: CleanupDataKind.cache.minimumAgeDays, worktree: false,
        now: now.addingTimeInterval(23 * 3_600))
    }
  }

  @Test func preferencesStartManualAndClampPersistedValues() throws {
    let defaults = try #require(UserDefaults(suiteName: "cleaner-policy-\(UUID())"))
    var settings = CleanerPreferences.load(defaults)
    #expect(settings.mode == .manual)
    #expect(!settings.categories.contains(.worktrees))
    settings.freeSpaceGB = -50
    settings.automaticFreeSpaceGB = 4_000
    settings.worktreeDays = 4_000
    settings.categories = [.claude, .docker]
    settings.save(defaults)
    let loaded = CleanerPreferences.load(defaults)
    #expect(loaded.freeSpaceGB == 1)
    #expect(loaded.automaticFreeSpaceGB == 1_000)
    #expect(loaded.checkMinutes == 25)
    #expect(loaded.worktreeDays == 365)
    #expect(loaded.categories == [.claude, .docker])
    #expect(!loaded.isBelowThreshold(nil))
    #expect(!loaded.isBelowThreshold(1_000_000_000))
    #expect(loaded.isBelowThreshold(999_999_999))
    #expect(!loaded.isBelowThreshold(nil, automatic: true))
    #expect(!loaded.isBelowThreshold(1_000_000_000_000, automatic: true))
    #expect(loaded.isBelowThreshold(999_999_999_999, automatic: true))
  }

  @Test func separateLimitsMigrateTheSavedSharedValueAndPersistIndependently() throws {
    let old = try JSONSerialization.data(withJSONObject: [
      "mode": "automatic", "freeSpaceGB": 37,
    ])
    var preferences = try JSONDecoder().decode(CleanerPreferences.self, from: old)
    #expect(preferences.freeSpaceGB == 37 && preferences.automaticFreeSpaceGB == 37)
    preferences.automaticFreeSpaceGB = 9
    let restored = try JSONDecoder().decode(
      CleanerPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored.freeSpaceGB == 37 && restored.automaticFreeSpaceGB == 9)
    #expect(restored.isBelowThreshold(20_000_000_000))
    #expect(!restored.isBelowThreshold(20_000_000_000, automatic: true))
  }

  @Test func oldCheckIntervalsCannotOverrideTheFixedSchedule() throws {
    let name = "cleaner-interval-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var preferences = CleanerPreferences()
    preferences.mode = .notify
    preferences.freeSpaceGB = 18
    var stored = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
    for oldInterval in [0, 60, 1_440] {
      stored["checkMinutes"] = oldInterval
      defaults.set(
        try JSONSerialization.data(withJSONObject: stored), forKey: CleanerPreferences.key)
      let restored = CleanerPreferences.load(defaults)
      #expect(restored.checkMinutes == 25)
      #expect(restored.mode == .notify && restored.freeSpaceGB == 18)
    }
  }

  @Test func oldModesRestoreWithoutEnablingAdditionalBackgroundActions() throws {
    for mode in [CleanerMode.manual, .notify, .automatic] {
      let data = try JSONSerialization.data(withJSONObject: ["mode": mode.rawValue])
      let restored = try JSONDecoder().decode(CleanerPreferences.self, from: data)
      #expect(restored.mode == mode)
      #expect(restored.warningsEnabled == (mode == .notify))
      #expect(!restored.categories.isEmpty)
      #expect(restored.checkMinutes == 25)
    }
  }

  @Test func notificationAndAutomaticSwitchesPreserveEachOthersState() throws {
    var preferences = CleanerPreferences()
    preferences.warningsEnabled = true
    preferences.setAutomatic(true)
    #expect(preferences.mode == .automatic && preferences.warningsEnabled)
    let stored = try JSONEncoder().encode(preferences)
    preferences = try JSONDecoder().decode(CleanerPreferences.self, from: stored)
    #expect(preferences.mode == .automatic && preferences.warningsEnabled)
    preferences.warningsEnabled = false
    #expect(preferences.mode == .automatic && !preferences.warningsEnabled)
    preferences.setAutomatic(false)
    #expect(preferences.mode == .manual)
    preferences.warningsEnabled = true
    preferences.setAutomatic(true)
    preferences.setAutomatic(false)
    #expect(preferences.mode == .notify && preferences.warningsEnabled)
  }

  @Test func cacheAllowlistExcludesSessionsCredentialsPluginsAndWholeAppProfiles() {
    let home = "/Users/fixture"
    let paths = CleanerCategory.allCases.flatMap { CleanerCatalog.rules($0, home: home) }.map(
      \.path)
    #expect(paths.contains(home + "/Library/Caches/com.zarifpour.superconductor"))
    #expect(paths.contains(home + "/Library/Caches/com.openai.codex"))
    for path in paths {
      #expect(!path.contains("/sessions"))
      #expect(!path.contains("/plugins"))
      #expect(!path.contains("/auth"))
      #expect(
        ![home + "/.codex", home + "/.claude", home + "/Library/Application Support/Codex"]
          .contains(path))
    }
    #expect(Set(paths).count == paths.count)
  }

  @Test func buildOutputRequiresIgnoredUntrackedDirectoryAndManifest() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("package.json", "{}")
    try fixture.write("dist/output.js", "generated")
    try fixture.git(["init", "-b", "main"])
    #expect(throws: (any Error).self) {
      try CleanerProjectSafety.validateBuild(path: fixture.path + "/dist", project: fixture.path)
    }
    try fixture.write(".gitignore", "dist/\n")
    try CleanerProjectSafety.validateBuild(path: fixture.path + "/dist", project: fixture.path)
    try fixture.git(["add", "-f", "dist/output.js"])
    #expect(throws: (any Error).self) {
      try CleanerProjectSafety.validateBuild(path: fixture.path + "/dist", project: fixture.path)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.path + "/dist/output.js"))
    #expect(throws: (any Error).self) {
      try CleanerProjectSafety.validateActivity(fixture.path, active: [fixture.path + "/src"])
    }
    #expect(throws: (any Error).self) {
      try CleanerProjectSafety.validateActivity(fixture.path, active: nil)
    }
  }

  @Test func discoveryFindsMonorepoProjectsAndSkipsGeneratedTrees() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write(".git", "gitdir: fixture")
    try fixture.write("apps/web/package.json", "{}")
    try fixture.write("apps/web/.next/package.json", "{}")
    try fixture.write("rust/Cargo.toml", "fixture")
    try fixture.write("rust/target/package.json", "{}")
    let discovery = DeveloperArtifactScanner.discover(
      .init(roots: [fixture.path], maximumEntries: 100, maximumDepth: 8))
    #expect(discovery.projects == [fixture.path + "/apps/web", fixture.path + "/rust"])
  }

  @Test func worktreeAgeIncludesGitMetadataAndCanBeAdjusted() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.git(["init", "-b", "main"])
    try fixture.git(["config", "user.name", "Fixture"])
    try fixture.git(["config", "user.email", "fixture@example.invalid"])
    try fixture.git(["config", "commit.gpgsign", "false"])
    try fixture.write("source.txt", "keep me")
    try fixture.git(["add", "source.txt"])
    try fixture.git(["commit", "-m", "fixture"])
    try fixture.git(["worktree", "add", "-b", "topic", fixture.path + "/linked"])
    let path = fixture.path + "/linked"
    let tree = try CacheCleaner.tree(.init(path: path))
    let future = Date.now.addingTimeInterval(10 * 86_400)
    try CleanerProjectSafety.validateAge(
      path: path, tree: tree, days: 7, worktree: true, now: future)
    #expect(throws: (any Error).self) {
      try CleanerProjectSafety.validateAge(
        path: path, tree: tree, days: 30, worktree: true, now: future)
    }
    let gitDir = DeveloperCommand.git(
      .init(directory: path, arguments: ["rev-parse", "--absolute-git-dir"])
    )
    .output.trimmingCharacters(in: .whitespacesAndNewlines)
    try FileManager.default.setAttributes(
      [.modificationDate: future], ofItemAtPath: gitDir + "/HEAD")
    #expect(throws: (any Error).self) {
      try CleanerProjectSafety.validateAge(
        path: path, tree: tree, days: 7, worktree: true, now: future)
    }
  }

  @Test func cleanerRejectsChangedAndUnselectedFixturesBeforeRemoval() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/entry", "old cache")
    let path = fixture.path + "/cache/entry"
    let old = Date.now.addingTimeInterval(-10 * 86_400)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
    let rule = CacheRule(
      title: "Fixture", path: fixture.path + "/cache", recipe: "Rebuild", owners: [], kind: .cache)
    let tree = try CacheCleaner.tree(.init(path: path))
    let item = CleanerItem(
      category: .claude, path: path, bytes: tree.bytes,
      target: .cache(.init(path: path, rule: rule, tree: tree)))
    var prefs = CleanerPreferences()
    prefs.categories = []
    await #expect(throws: (any Error).self) {
      try await NativeCleanerDriver().remove(item, preferences: prefs)
    }
    prefs.categories = [.claude]
    try fixture.write("cache/entry", "recent changed cache")
    await #expect(throws: (any Error).self) {
      try await NativeCleanerDriver().remove(item, preferences: prefs)
    }
    #expect(FileManager.default.fileExists(atPath: path))
  }
}

@MainActor
struct CleanerModelTests {
  @Test func automaticCleanupUsesItsOwnLimitIndependentlyOfWarnings() async throws {
    let context = try context(available: 10_000_000_000)
    defer { context.fixture.remove() }
    let model = context.model
    model.preferences.warningsEnabled = true
    model.preferences.freeSpaceGB = 20
    model.preferences.automaticFreeSpaceGB = 5
    model.preferences.setAutomatic(true)
    let now = Date.now.addingTimeInterval(4_000)
    await model.backgroundCheck(now: now)
    #expect(model.lowSpaceWarning)
    #expect(await context.driver.scanCount == 0)

    model.preferences.freeSpaceGB = 1
    model.preferences.automaticFreeSpaceGB = 15
    #expect(!model.lowSpaceWarning)
    await model.backgroundCheck(now: now.addingTimeInterval(25 * 60))
    #expect(await context.driver.scanCount == 1)
    #expect(await context.driver.automaticRemovals == [true, true])
  }

  @Test func lowSpaceWarningTracksThresholdRecoveryAndSwitchWithoutDeleting() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let model = context.model
    await model.refreshDisk()
    #expect(!model.lowSpaceWarning)
    model.preferences.warningsEnabled = true
    #expect(model.lowSpaceWarning)
    model.preferences.freeSpaceGB = 1
    #expect(!model.lowSpaceWarning)
    model.preferences.freeSpaceGB = 20
    #expect(model.lowSpaceWarning)
    await context.driver.setAvailable(30_000_000_000)
    await model.refreshDisk()
    #expect(!model.lowSpaceWarning)
    await context.driver.setAvailable(nil)
    await model.refreshDisk()
    #expect(!model.lowSpaceWarning)
    await context.driver.setAvailable(1_000_000_000)
    await model.refreshDisk()
    model.preferences.warningsEnabled = false
    #expect(!model.lowSpaceWarning)
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func categoryPreviewAndIndividualDeletionAreIndependentOfBulkSelections() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let model = context.model
    await model.loadCategory(.worktrees)
    #expect(model.preferences.categories == [.claude])
    #expect(model.scan == nil)
    #expect(await context.driver.scanPreferences.first?.categories == [.worktrees])
    let item = try #require(model.categoryScans[.worktrees]?.items.first)
    await model.deleteItem(item)
    #expect(await context.driver.removals == ["fixture-one"])
    #expect(await context.driver.automaticRemovals == [false])
    #expect(await context.driver.removalPreferences.first?.categories == [.claude, .worktrees])
    #expect(model.preferences.categories == [.claude])
    #expect(model.categoryScans[.worktrees]?.items.map(\.path) == ["fixture-two"])
    #expect(try context.history.load().wins.count == 1)
  }

  @Test func categoryRefreshReusesThirtySecondsThenClearsExpiredItemsBeforeScanning() async throws {
    let clock = CleanerFixtureClock()
    let context = try context(now: { clock.date })
    defer { context.fixture.remove() }
    let model = context.model
    await model.loadCategory(.worktrees)
    let previous = try #require(model.categoryScans[.worktrees])
    await context.driver.setScanPaths(["new-worktree"])
    for offset in [1.0, 29.0, 30.0] {
      clock.date = previous.scannedAt.addingTimeInterval(offset)
      await model.loadCategory(.worktrees)
      #expect(await context.driver.scanCount == 1)
      #expect(model.categoryScans[.worktrees]?.scannedAt == previous.scannedAt)
      #expect(!model.isBusy && model.loadingCategory == nil)
    }
    clock.date = previous.scannedAt.addingTimeInterval(30.001)
    model.prepareCategory(.worktrees)
    #expect(model.categoryScans[.worktrees] == nil)
    let refresh = Task { await model.loadCategory(.worktrees) }
    for _ in 0..<100 {
      if await context.driver.scanCount == 2 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(model.loadingCategory == .worktrees && model.isBusy)
    #expect(model.categoryScans[.worktrees] == nil)
    #expect(model.status.isEmpty)
    await model.deleteItem(try #require(previous.items.first))
    #expect(await context.driver.removals.isEmpty)
    await refresh.value
    #expect(model.categoryScans[.worktrees]?.items.map(\.path) == ["new-worktree"])
    #expect(model.loadingCategory == nil && !model.isBusy)
    #expect(await context.driver.scanCount == 2)
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func stoppedCategoryLoadAndUnknownItemsCannotDelete() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let task = Task { await context.model.loadCategory(.worktrees) }
    for _ in 0..<100 {
      if await context.driver.scanCount > 0 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    context.model.requestStop()
    await task.value
    #expect(context.model.categoryScans[.worktrees] == nil)
    let unknown = CleanerItem(category: .worktrees, path: "unknown", bytes: 1, target: .docker)
    await context.model.deleteItem(unknown)
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func categoryCacheStartsAtCompletionAndIncludesEmptyResults() async throws {
    let clock = CleanerFixtureClock()
    let context = try context(now: { clock.date })
    defer { context.fixture.remove() }
    await context.driver.setScanPaths([])
    let load = Task { await context.model.loadCategory(.worktrees) }
    for _ in 0..<100 {
      if await context.driver.scanCount == 1 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    clock.date = clock.date.addingTimeInterval(90)
    await load.value
    #expect(context.model.categoryScans[.worktrees]?.scannedAt == clock.date)
    await context.model.loadCategory(.worktrees)
    #expect(context.model.categoryScans[.worktrees]?.items.isEmpty == true)
    #expect(await context.driver.scanCount == 1)
    await context.model.loadCategory(.dependencies)
    #expect(await context.driver.scanCount == 2)
  }

  @Test func changingProjectScopeClearsFreshResultsAndDiscardsInFlightResults() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    await context.model.loadCategory(.worktrees)
    context.model.preferences.projectRoots = [context.fixture.path]
    #expect(context.model.categoryScans.isEmpty)
    let load = Task { await context.model.loadCategory(.worktrees) }
    for _ in 0..<100 {
      if await context.driver.scanCount == 2 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    context.model.preferences.worktreeDays += 1
    await load.value
    #expect(context.model.categoryScans.isEmpty)
    await context.model.loadCategory(.worktrees)
    #expect(await context.driver.scanCount == 3)
  }

  @Test func cleanReusesFreshCategoriesAndScansOnlyMissingOrExpiredOnes() async throws {
    let clock = CleanerFixtureClock()
    let context = try context(now: { clock.date })
    defer { context.fixture.remove() }
    let model = context.model
    await model.loadCategory(.claude)
    await context.driver.setScanPaths(["codex-cache"])
    model.preferences.categories = [.claude, .codex]
    await model.cleanSelected()
    #expect(await context.driver.scanCount == 2)
    #expect(await context.driver.scanPreferences.last?.categories == [.codex])
    #expect(Set(await context.driver.removals) == ["fixture-one", "fixture-two", "codex-cache"])
    #expect(model.categoryScans[.claude]?.items.isEmpty == true)
    #expect(model.categoryScans[.codex]?.items.isEmpty == true)
    await model.cleanSelected()
    #expect(await context.driver.scanCount == 2)
    clock.date = clock.date.addingTimeInterval(31)
    await context.driver.setScanPaths([])
    await model.scanNow()
    #expect(await context.driver.scanCount == 3)
    #expect(await context.driver.scanPreferences.last?.categories == [.claude, .codex])
  }

  @Test func combiningCachedWorktreesAndDependenciesNeverDeletesOverlappingPaths() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let model = context.model
    await context.driver.setScanPaths(["checkout/node_modules"])
    await model.loadCategory(.dependencies)
    await context.driver.setScanPaths(["checkout"])
    await model.loadCategory(.worktrees)
    model.preferences.categories = [.dependencies, .worktrees]
    await model.cleanSelected()
    #expect(await context.driver.scanCount == 2)
    #expect(await context.driver.removals == ["checkout"])
    #expect(model.categoryScans[.dependencies]?.items.isEmpty == true)
    #expect(model.categoryScans[.worktrees]?.items.isEmpty == true)
  }

  @Test func automaticCleanupClearsManualCacheAndScansWithItsOwnAgePolicy() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let model = context.model
    await model.loadCategory(.claude)
    model.preferences.mode = .automatic
    let automatic = Task { await model.backgroundCheck(now: .distantFuture) }
    for _ in 0..<100 {
      if await context.driver.scanCount == 2 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(model.categoryScans[.claude] == nil)
    await automatic.value
    #expect(await context.driver.automaticScans == [false, true])
    #expect(model.categoryScans[.claude] == nil)
    await model.loadCategory(.claude)
    #expect(await context.driver.automaticScans == [false, true, false])
  }

  @Test func refreshBypassesFreshCachesWithoutDeletingOrChangingSelections() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let model = context.model
    await model.loadCategory(.claude)
    await model.loadCategory(.codex)
    #expect(await context.driver.scanCount == 2)
    await context.driver.setScanPaths([])
    await model.refreshScans()
    #expect(await context.driver.scanCount == 3)
    #expect(model.categoryScans[.claude]?.items.isEmpty == true)
    #expect(model.categoryScans[.codex] != nil)
    #expect(model.preferences.categories == [.claude])
    #expect(await context.driver.removals.isEmpty)
    #expect(!model.isBusy)
    #expect(model.status == "Scans refreshed.")
    await model.loadCategory(.codex)
    #expect(await context.driver.scanCount == 3)
  }

  @Test func refreshDoesNotStartAnotherScanWhileBusy() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let first = Task { await context.model.refreshScans() }
    for _ in 0..<100 {
      if await context.driver.scanCount > 0 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    await context.model.refreshScans()
    await first.value
    #expect(await context.driver.scanCount == 1)
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func directDeletionFailureStaysVisibleAndCanBeRetried() async throws {
    let context = try context(fails: true)
    defer { context.fixture.remove() }
    let model = context.model
    await model.loadCategory(.claude)
    let item = try #require(model.categoryScans[.claude]?.items.first)
    await model.deleteItem(item)
    #expect(model.itemFailures[item.id] == "Fixture is in use")
    #expect(model.categoryScans[.claude]?.items.contains { $0.id == item.id } == true)
    #expect(model.outcome?.removed == 0 && model.outcome?.kept == 1)
    #expect(try context.history.load().wins.isEmpty)
    await context.driver.setFails(false)
    await model.deleteItem(item)
    #expect(model.itemFailures[item.id] == nil)
    #expect(model.removingItemID == nil)
    #expect(model.categoryScans[.claude]?.items.contains { $0.id == item.id } == false)
    #expect(try context.history.load().wins.count == 1)
  }

  @Test func cleanActionScansAndDeletesInOneOperation() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    context.model.preferences.mode = .automatic
    await context.model.cleanSelected()
    #expect(await context.driver.scanCount == 1)
    #expect(await context.driver.automaticScans == [false])
    #expect(await context.driver.removals == ["fixture-one", "fixture-two"])
    #expect(await context.driver.automaticRemovals == [false, false])
    #expect(context.model.scan?.items.isEmpty == true)
    #expect(context.model.outcome?.removed == 2)
    #expect(try context.history.load().wins.count == 2)
  }

  @Test func stoppingCleanDuringScanDoesNotDelete() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let task = Task { await context.model.cleanSelected() }
    for _ in 0..<100 {
      if await context.driver.scanCount > 0 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    context.model.requestStop()
    await task.value
    #expect(!context.model.isBusy && context.model.outcome == nil)
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func cleanupFeedbackExpiresWithoutClearingNewerStatusOrHistory() async throws {
    let completed = try context()
    let refreshed = try context()
    defer {
      completed.fixture.remove()
      refreshed.fixture.remove()
    }
    await completed.model.cleanSelected()
    #expect(completed.model.status.hasPrefix("Removed 2 items · "))
    await refreshed.model.loadCategory(.claude)
    let item = try #require(refreshed.model.categoryScans[.claude]?.items.first)
    await refreshed.model.deleteItem(item)
    #expect(refreshed.model.status.hasPrefix("Removed 1 item · "))
    await refreshed.model.scanNow()
    let newerStatus = refreshed.model.status

    try await Task.sleep(for: .milliseconds(5_400))

    #expect(completed.model.status.isEmpty)
    #expect(completed.model.outcome?.removed == 2)
    #expect(try completed.history.load().wins.count == 2)
    #expect(refreshed.model.status == newerStatus && !newerStatus.isEmpty)
  }

  @Test func manualAndNotifyNeverAutomaticallyDelete() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let model = context.model
    await model.backgroundCheck(now: .distantFuture)
    #expect(await context.driver.scanCount == 0)
    model.preferences.mode = .notify
    await model.backgroundCheck(now: .distantFuture)
    #expect(await context.driver.removals.isEmpty)
    #expect(await context.driver.scanCount == 0)
  }

  @Test func backgroundChecksWaitTwentyFiveMinutesBetweenRuns() async throws {
    let context = try context(available: 80_000_000_000)
    defer { context.fixture.remove() }
    let model = context.model
    model.preferences.mode = .notify
    let now = Date.now.addingTimeInterval(2_000)
    await model.backgroundCheck(now: now)
    #expect(model.nextCheck == now.addingTimeInterval(25 * 60))
    await model.backgroundCheck(now: now.addingTimeInterval(25 * 60 - 1))
    #expect(model.nextCheck == now.addingTimeInterval(25 * 60))
    await model.backgroundCheck(now: now.addingTimeInterval(25 * 60))
    #expect(model.nextCheck == now.addingTimeInterval(50 * 60))
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func notificationsDoNotPreventAnEnabledAutomaticCleanup() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    context.model.preferences.warningsEnabled = true
    context.model.preferences.setAutomatic(true)
    await context.model.backgroundCheck(now: .now.addingTimeInterval(4_000))
    #expect(context.model.preferences.warningsEnabled)
    #expect(await context.driver.scanCount == 1)
    #expect(await context.driver.removals == ["fixture-one", "fixture-two"])
  }

  @Test func automaticUsesFreshScanAndNeverRunsAboveThresholdOrWithUnknownCapacity() async throws {
    for available: UInt64? in [nil, 50_000_000_000] {
      let context = try context(available: available)
      defer { context.fixture.remove() }
      context.model.preferences.mode = .automatic
      await context.model.backgroundCheck(now: .distantFuture)
      #expect(await context.driver.scanCount == 0)
      #expect(await context.driver.removals.isEmpty)
    }
    let context = try context()
    defer { context.fixture.remove() }
    context.model.preferences.mode = .automatic
    await context.model.backgroundCheck(now: .now.addingTimeInterval(4_000))
    #expect(await context.driver.scanCount == 1)
    #expect(await context.driver.removals == ["fixture-one", "fixture-two"])
    #expect(context.model.outcome?.removed == 2)
    #expect(await context.driver.automaticScans == [true])
    #expect(await context.driver.automaticRemovals == [true, true])
    await context.model.backgroundCheck()
    #expect(await context.driver.scanCount == 1)
    #expect(try context.history.load().wins.count == 2)
  }

  @Test func cleanActionUsesCurrentCategoriesAndAFreshInventory() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    await context.model.scanNow()
    context.model.preferences.categories = [.codex]
    #expect(context.model.scan == nil)
    await context.driver.setScanPaths(["fresh-cache"])
    await context.model.cleanSelected()
    #expect(await context.driver.removals == ["fresh-cache"])
    #expect(await context.driver.removalPreferences.first?.categories == [.codex])
  }

  @Test func concurrentCleanClicksAreSerializedAndFailuresStayVisible() async throws {
    let context = try context(fails: true)
    defer { context.fixture.remove() }
    async let first: Void = context.model.cleanSelected()
    async let second: Void = context.model.cleanSelected()
    _ = await (first, second)
    #expect(await context.driver.scanCount == 1)
    #expect(context.model.outcome?.kept == 2)
    #expect(context.model.scan?.items.count == 2)
    #expect(context.model.scan?.notes.count == 2)
    #expect(context.model.itemFailures.count == 2)
    #expect(try context.history.load().wins.isEmpty)
  }

  @Test func changingModeDuringAutomaticScanStopsDeletion() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    context.model.preferences.mode = .automatic
    let task = Task { await context.model.backgroundCheck(now: .distantFuture) }
    for _ in 0..<100 {
      if await context.driver.scanCount > 0 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    context.model.preferences.mode = .manual
    await task.value
    #expect(await context.driver.removals.isEmpty)
    #expect(!context.model.isBusy)
  }

  @Test func recoveredFreeSpaceDuringScanPreventsDeletion() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let driver = FixtureCleanerDriver(available: 1_000_000_000, recoversAfterScan: true)
    let defaults = try #require(UserDefaults(suiteName: "cleaner-recovery-\(UUID())"))
    let model = CleanerModel(
      defaults: defaults, driver: driver,
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    model.preferences.mode = .automatic
    await model.backgroundCheck(now: .distantFuture)
    #expect(await driver.scanCount == 1)
    #expect(await driver.removals.isEmpty)
  }

  @Test func stopDuringAutomaticScanPreventsDeletion() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    context.model.preferences.mode = .automatic
    let task = Task { await context.model.backgroundCheck(now: .distantFuture) }
    for _ in 0..<100 {
      if await context.driver.scanCount > 0 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    context.model.requestStop()
    await task.value
    #expect(await context.driver.removals.isEmpty)
    #expect(!context.model.isBusy)
    #expect(context.model.status == "Automatic cleanup stopped. Nothing was deleted.")
  }

  @Test func cleanupPublishesEachVerifiedRemovalBeforeShowingItsResult() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    var snapshots: [CleanerCleanup] = []
    let subscription = context.model.$cleanup.sink { if let run = $0 { snapshots.append(run) } }
    await context.model.cleanSelected()
    withExtendedLifetime(subscription) {}
    #expect(snapshots.first?.phase == .scanning)
    #expect(snapshots.contains { $0.phase == .removing && $0.removedIDs.count == 1 })
    #expect(snapshots.contains { $0.phase == .removing && $0.removedIDs.count == 2 })
    let result = try #require(context.model.cleanup)
    #expect(result.phase == .finished)
    #expect(result.result?.removed == 2)
    #expect(result.result?.kept == 0)
    #expect(context.model.removedItemIDs == result.removedIDs)
    context.model.panelClosed()
    #expect(context.model.removedItemIDs.isEmpty)
    #expect(context.model.cleanup == nil)
    #expect(context.model.status.isEmpty)
    #expect(context.model.outcome?.removed == 2)
  }

  @Test func closingDuringCleanupDoesNotStopDeletionOrReopenItsResult() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    let task = Task { await context.model.cleanSelected() }
    try await Task.sleep(for: .milliseconds(10))
    #expect(context.model.cleanup?.phase == .scanning)
    context.model.panelClosed()
    await task.value
    #expect(context.model.cleanup == nil)
    #expect(context.model.outcome?.removed == 2)
    #expect(!context.model.stopRequested)
    #expect(!context.model.isBusy)
  }

  @Test func failedItemsStayInTheResultAndNeverCollapse() async throws {
    let context = try context(fails: true)
    defer { context.fixture.remove() }
    await context.model.cleanSelected()
    let result = try #require(context.model.cleanup)
    #expect(result.phase == .finished)
    #expect(result.removedIDs.isEmpty)
    #expect(context.model.removedItemIDs.isEmpty)
    #expect(result.result?.kept == 2)
    #expect(result.result?.removed == 0)
    #expect(result.items.allSatisfy { context.model.itemFailures[$0.id] != nil })
  }

  @Test func emptyCleanupHasANothingToCleanResult() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    await context.driver.setScanPaths([])
    await context.model.cleanSelected()
    #expect(context.model.cleanup?.phase == .finished)
    #expect(context.model.cleanup?.items.isEmpty == true)
    #expect(context.model.cleanup?.result?.removed == 0)
    #expect(await context.driver.removals.isEmpty)
  }

  @Test func singleDeleteAndBackgroundCleanupDoNotShowBulkResult() async throws {
    let context = try context()
    defer { context.fixture.remove() }
    await context.model.loadCategory(.claude)
    let item = try #require(context.model.categoryScans[.claude]?.items.first)
    await context.model.deleteItem(item)
    #expect(context.model.cleanup == nil)
    context.model.preferences.setAutomatic(true)
    await context.model.backgroundCheck(now: .distantFuture)
    #expect(context.model.cleanup == nil)
  }

  private func context(
    available: UInt64? = 1_000_000_000, fails: Bool = false,
    now: @escaping () -> Date = { .now }
  ) throws -> (
    model: CleanerModel, driver: FixtureCleanerDriver, fixture: CleanerFixture,
    history: CleanupHistoryStore
  ) {
    let fixture = try CleanerFixture()
    let defaults = try #require(UserDefaults(suiteName: "cleaner-model-\(UUID())"))
    let history = CleanupHistoryStore(url: URL(fileURLWithPath: fixture.path + "/history.json"))
    let driver = FixtureCleanerDriver(available: available, fails: fails)
    let model = CleanerModel(defaults: defaults, driver: driver, history: history, now: now)
    model.preferences.categories = [.claude]
    return (model, driver, fixture, history)
  }
}

@MainActor
private final class CleanerFixtureClock {
  var date = Date(timeIntervalSince1970: 1_792_000_000)
}

actor FixtureCleanerDriver: CleanerDriver {
  var available: UInt64?
  var fails: Bool
  let recoversAfterScan: Bool
  var scanCount = 0
  var automaticScans: [Bool] = []
  var automaticRemovals: [Bool] = []
  var scanPreferences: [CleanerPreferences] = []
  var removalPreferences: [CleanerPreferences] = []
  var removals: [String] = []
  private var scanPaths = ["fixture-one", "fixture-two"]
  init(available: UInt64? = 80_000_000_000, fails: Bool = false, recoversAfterScan: Bool = false) {
    self.available = available
    self.fails = fails
    self.recoversAfterScan = recoversAfterScan
  }
  func availableBytes() -> UInt64? {
    recoversAfterScan && scanCount > 0 ? 80_000_000_000 : available
  }
  func setAvailable(_ bytes: UInt64?) { available = bytes }
  func setFails(_ value: Bool) { fails = value }
  func setScanPaths(_ paths: [String]) { scanPaths = paths }
  func scan(_ preferences: CleanerPreferences, automatic: Bool) async -> CleanerScan {
    scanCount += 1
    automaticScans.append(automatic)
    scanPreferences.append(preferences)
    try? await Task.sleep(for: .milliseconds(50))
    return .init(
      items: scanPaths.map {
        .init(
          category: CleanerCategory.allCases.first(where: preferences.categories.contains)
            ?? .claude,
          path: $0, bytes: 1_000_000_000, target: .docker)
      })
  }
  func remove(_ item: CleanerItem, preferences: CleanerPreferences, automatic: Bool) throws
    -> CleanupWin
  {
    automaticRemovals.append(automatic)
    removalPreferences.append(preferences)
    if fails { throw CleanerError.kept("Fixture is in use") }
    removals.append(item.path)
    return .init(
      id: UUID().uuidString, date: .now, title: "Fixture", paths: [item.path], before: nil,
      after: nil, bytes: item.bytes)
  }
}

struct CleanerFixture {
  let path: String
  init() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    path = try #require(ReviewFile.canonicalPath(url.path))
  }
  func write(_ name: String, _ text: String) throws {
    let url = URL(fileURLWithPath: path + "/" + name)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }
  func git(_ arguments: [String]) throws {
    let result = DeveloperCommand.git(.init(directory: path, arguments: arguments))
    try #require(result.status == 0)
  }
  func remove() { try? FileManager.default.removeItem(atPath: path) }
}
