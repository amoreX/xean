import Foundation
import Testing

@testable import BlitzClean

@MainActor
struct CleanerEstimateTests {
  @Test func openingScansWithoutDeletionAndReusesFreshResults() async throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let driver = FixtureCleanerDriver()
    let model = CleanerModel(defaults: defaults, driver: driver)
    model.preferences.categories = [.packages]
    #expect(model.reclaimableBytes == nil)
    model.panelOpened()
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.reclaimableBytes == 2_000_000_000)
    #expect(await driver.removals.isEmpty)
    model.panelClosed()
    model.panelOpened()
    try await Task.sleep(for: .milliseconds(150))
    #expect(await driver.scanCount == 1)
    model.preferences.categories = [.builds]
    try await Task.sleep(for: .milliseconds(200))
    #expect(await driver.scanCount == 2)
    #expect(model.reclaimableBytes == 2_000_000_000)
    model.preferences.categories = []
    #expect(model.reclaimableBytes == 0)
    model.panelClosed()
  }

  @Test func backgroundEstimateRunsWhileClosedWithoutLockingControls() async throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let driver = FixtureCleanerDriver()
    let model = CleanerModel(defaults: defaults, driver: driver)
    model.preferences.categories = [.packages]
    model.start()
    defer { model.stop() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(!model.isBusy)
    model.panelClosed()
    try await Task.sleep(for: .milliseconds(150))
    #expect(model.reclaimableBytes == 2_000_000_000)
    #expect(model.status.isEmpty)
    #expect(await driver.removals.isEmpty)
    model.panelOpened()
    #expect(!model.isBusy)
    #expect(model.reclaimableBytes == 2_000_000_000)
    model.panelClosed()
  }

  @Test func cleanCancelsEstimateAndUsesFreshScan() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let driver = FixtureCleanerDriver()
    let model = CleanerModel(
      defaults: defaults, driver: driver,
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    model.preferences.categories = [.packages]
    model.start()
    defer { model.stop() }
    try await Task.sleep(for: .milliseconds(20))
    await driver.setScanPaths(["fresh-only"])
    await model.cleanSelected()
    #expect(await driver.scanCount == 2)
    #expect(await driver.removals == ["fresh-only"])
    #expect(model.reclaimableBytes == 0)
  }

  @Test func selectionChangesDuringScanAreRescanned() async throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let driver = FixtureCleanerDriver()
    let model = CleanerModel(defaults: defaults, driver: driver)
    model.preferences.categories = [.packages]
    model.panelOpened()
    try await Task.sleep(for: .milliseconds(20))
    model.preferences.categories = [.builds]
    try await Task.sleep(for: .milliseconds(250))
    #expect(model.categoryScans[.builds] != nil)
    #expect(model.reclaimableBytes == 2_000_000_000)
    #expect(await driver.removals.isEmpty)
    model.panelClosed()
  }
}
