import Foundation
import Testing

@testable import BlitzClean

@MainActor
struct CleanerParallelDeletionTests {
  @Test func boundsConcurrencyAndRecordsEachSuccessAndFailure() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let driver = ParallelDeletionDriver()
    let defaults = try #require(UserDefaults(suiteName: "parallel-cleaner-\(UUID())"))
    let history = CleanupHistoryStore(url: URL(fileURLWithPath: fixture.path + "/history.json"))
    let model = CleanerModel(defaults: defaults, driver: driver, history: history)
    model.preferences.categories = [.claude]
    await model.cleanSelected()
    #expect(await driver.maximumActive == 3)
    #expect(await driver.started == 8)
    #expect(model.outcome?.removed == 7)
    #expect(model.outcome?.kept == 1)
    #expect(model.cleanup?.removedIDs.count == 7)
    #expect(model.itemFailures.count == 1)
    #expect(try history.load().wins.count == 7)
    #expect(model.removingItemIDs.isEmpty)
  }

  @Test func stopKeepsQueuedItemsAndAccountsForInFlightRemovals() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let driver = ParallelDeletionDriver()
    let defaults = try #require(UserDefaults(suiteName: "parallel-stop-\(UUID())"))
    let model = CleanerModel(
      defaults: defaults, driver: driver,
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    model.preferences.categories = [.claude]
    let run = Task { await model.cleanSelected() }
    for _ in 0..<200 {
      if await driver.started == 3 { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await driver.started == 3)
    model.requestStop()
    await run.value
    #expect(await driver.started == 3)
    #expect(model.outcome?.removed == 3)
    #expect(model.outcome?.kept == 5)
    #expect(!model.isBusy)
  }

  @Test func overlappingPathsAndSharedStateCannotRunTogether() {
    let parent = ParallelDeletionDriver.item("/cache/a")
    let child = ParallelDeletionDriver.item("/cache/a/child")
    let sibling = ParallelDeletionDriver.item("/cache/ab")
    #expect(!CleanerDeletionResult.canStart(parent, alongside: [child]))
    #expect(!CleanerDeletionResult.canStart(child, alongside: [parent]))
    #expect(CleanerDeletionResult.canStart(sibling, alongside: [parent]))
    let docker = CleanerItem(
      category: .docker, path: "docker://local/build-cache", bytes: 1, target: .docker)
    #expect(!CleanerDeletionResult.canStart(docker, alongside: [parent]))
    #expect(!CleanerDeletionResult.canStart(parent, alongside: [docker]))
    #expect(CleanerDeletionResult.canStart(docker, alongside: []))
    guard case .cache(let candidate) = parent.target else { return }
    let build = CleanerItem(
      category: .builds, path: "/project/.next", bytes: 1,
      target: .build(candidate, project: "/project"))
    let dependency = ParallelDeletionDriver.item("/project/node_modules")
    #expect(!CleanerDeletionResult.canStart(build, alongside: [dependency]))
    let artifact = DeveloperArtifact(
      kind: .worktree, path: "/worktree", projectPath: "/worktree", technology: .node,
      bytes: 1, modifiedAt: .now, blocker: nil, identity: nil, worktree: nil,
      reinstallCommand: nil, internalVolume: true)
    let worktree = CleanerItem(
      category: .worktrees, path: "/worktree", bytes: 1,
      target: .artifact(artifact, tree: candidate.tree))
    #expect(!CleanerDeletionResult.canStart(worktree, alongside: [parent]))
    #expect(!CleanerDeletionResult.canStart(parent, alongside: [worktree]))
  }
}

private actor ParallelDeletionDriver: CleanerDriver {
  var active = 0
  var maximumActive = 0
  var started = 0

  nonisolated static func item(_ path: String) -> CleanerItem {
    let rule = CacheRule(
      title: "Fixture", path: "/cache", recipe: "Fixture", owners: [], kind: .cache)
    let candidate = CacheCandidate(
      path: path, rule: rule, tree: .init(fingerprint: "fixture", bytes: 1, newest: .distantPast))
    return .init(category: .claude, path: path, bytes: 1, target: .cache(candidate))
  }

  func scan(_ preferences: CleanerPreferences, automatic: Bool) -> CleanerScan {
    .init(items: (0..<8).map { Self.item("/cache/\($0)") })
  }

  func availableBytes() -> UInt64? { 80_000_000_000 }

  func remove(_ item: CleanerItem, preferences: CleanerPreferences, automatic: Bool) async throws
    -> CleanupWin
  {
    active += 1
    started += 1
    maximumActive = max(maximumActive, active)
    defer { active -= 1 }
    try await Task.sleep(for: .milliseconds(100))
    if item.path == "/cache/6" { throw CleanerError.kept("Fixture is in use") }
    return .init(
      id: UUID().uuidString, date: .now, title: "Fixture", paths: [item.path], before: nil,
      after: nil, bytes: 1)
  }
}
