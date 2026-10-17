import Foundation
import Testing

@testable import BlitzClean

@MainActor
struct CleanerMenuBarStatsTests {
  @Test func hidingStatsPersistsAndStopsPollingUntilEnabledAgain() async throws {
    let name = "cleaner-menu-stats-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var reads = 0
    let stats = CleanerMenuBarStats(defaults: defaults) {
      reads += 1
      return .empty
    }
    defer { stats.stop() }
    #expect(stats.enabled)
    stats.start()
    #expect(reads == 1 && stats.snapshot != nil)
    stats.enabled = false
    #expect(stats.snapshot == nil)
    #expect(!CleanerMenuBarStats(defaults: defaults).enabled)
    try await Task.sleep(for: .milliseconds(2_300))
    #expect(reads == 1)
    stats.enabled = true
    #expect(reads == 2 && stats.snapshot != nil)
    #expect(CleanerMenuBarStats(defaults: defaults).enabled)
  }

  @Test func displayUsesOriginalBlitzFormattingAndSelectedMetrics() {
    let snapshot = SystemSnapshot(
      .init(
        diskAvailable: 72_000_000_000, diskTotal: 500_000_000_000,
        ramAvailable: 4_000_000_000, ramTotal: 16_000_000_000, memoryPressure: .normal,
        cpuUsage: 0.25, thermalStatus: .nominal, updatedAt: .now))
    var display = CleanerMenuBarStats.Display()
    #expect(display.title(for: snapshot) == "72 GB disk free  CPU 25%  RAM 4 GB free")
    display.showMemory = false
    display.showDisk = false
    #expect(display.count == 1)
    #expect(display.title(for: snapshot) == "CPU 25%")
    #expect(display.title(for: .empty) == "CPU --")
    display.showCPU = false
    display.showMemory = true
    display.memoryDisplay = .used
    #expect(display.title(for: snapshot) == "RAM 12 GB used")
  }

  @Test func metricSelectionsReuseOriginalPreferencesAndPersist() throws {
    let name = "cleaner-menu-selection-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(false, forKey: MenuBarPreferenceKey.showCPU)
    defaults.set(false, forKey: MenuBarPreferenceKey.showDisk)
    let stats = CleanerMenuBarStats(defaults: defaults)
    #expect(stats.display.count == 1 && stats.display.showMemory)
    stats.display.memoryDisplay = .percentage
    stats.enabled = false
    let restored = CleanerMenuBarStats(defaults: defaults)
    #expect(restored.display == stats.display)
    #expect(!restored.enabled)
    restored.enabled = true
    #expect(restored.display.count == 1 && restored.display.showMemory)
    defaults.set(false, forKey: MenuBarPreferenceKey.showMemory)
    let fallback = CleanerMenuBarStats(defaults: defaults)
    #expect(fallback.display.count == 1 && fallback.display.showCPU)
  }
}
