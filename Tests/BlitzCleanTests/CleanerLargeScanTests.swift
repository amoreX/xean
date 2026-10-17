import Darwin
import Foundation
import Testing

@testable import BlitzClean

struct CleanerLargeScanTests {
  @Test func largeDependenciesScanRevalidateAndRemoveWithoutTruncation() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("project/package.json", "{}")
    try fixture.write("project/package-lock.json", "{}")
    try fixture.write("project/node_modules/zz-last", "original")
    let path = fixture.path + "/project/node_modules"
    try Self.createFiles(in: path, count: 60_010)

    var preferences = CleanerPreferences()
    preferences.categories = [.dependencies]
    var scan = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path], preferences: preferences, automatic: false, result: &scan)
    let item = try #require(scan.items.first { $0.path == path })
    #expect(scan.kept.isEmpty)
    guard case .artifact(_, let tree) = item.target else {
      Issue.record("Expected a dependency cleanup candidate")
      return
    }
    #expect(try CacheCleaner.tree(.init(path: path)) == tree)

    // A change after the old cutoff must still prevent removal.
    try fixture.write("project/node_modules/zz-last", "changed after scanning")
    await #expect(throws: CacheCleanError.changed) {
      try await NativeCleanerDriver().remove(item, preferences: preferences, automatic: false)
    }
    #expect(FileManager.default.fileExists(atPath: path + "/zz-last"))
    scan = CleanerScan()
    CleanerScanner.scanProjects(
      roots: [fixture.path], preferences: preferences, automatic: false, result: &scan)
    let refreshed = try #require(scan.items.first { $0.path == path })
    _ = try await NativeCleanerDriver().remove(
      refreshed, preferences: preferences, automatic: false)
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(FileManager.default.fileExists(atPath: fixture.path + "/project/package-lock.json"))
  }

  @Test func discoveryIncludesDeepProjectsBeyondFormerEntryAndResultLimits() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try Self.createFiles(in: fixture.path, count: 30_010)
    let nested = Array(repeating: "nested", count: 10).joined(separator: "/")
    for index in 0..<301 {
      let project = "\(nested)/project-\(index)"
      try fixture.write(project + "/package.json", "{}")
      try fixture.write(project + "/.git", "gitdir: fixture")
      try fixture.write(project + "/node_modules/package/keep", "fixture")
    }
    let discovery = DeveloperArtifactScanner.discover(.init(roots: [fixture.path]))
    #expect(!discovery.limited)
    #expect(discovery.projects.count == 301)
    #expect(discovery.repositories.count == 301)
    #expect(discovery.dependencies.count == 301)
  }

  @Test func treeTraversalHonorsCancellation() async throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let scan = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try CacheCleaner.tree(.init(path: fixture.path))
    }
    await #expect(throws: CancellationError.self) { try await scan.value }
  }

  private static func createFiles(in directory: String, count: Int) throws {
    for index in 0..<count {
      let descriptor = open(directory + "/file-\(index)", O_CREAT | O_EXCL | O_WRONLY, 0o600)
      guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      close(descriptor)
    }
  }
}
