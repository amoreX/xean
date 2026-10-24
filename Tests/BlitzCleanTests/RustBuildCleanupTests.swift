import Foundation
import Testing

@testable import BlitzClean

struct RustBuildCleanupTests {
  @Test func onlyCompilerDirectoriesAreCandidates() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    for name in RustBuildCleanup.names {
      try fixture.write("target/debug/\(name)/artifact", "generated")
    }
    try fixture.write("target/debug/del.app/Contents/MacOS/del", "running app")
    try fixture.write("target/debug/del", "executable")
    try fixture.write("target/debug/notes/important", "user data")
    let paths = RustBuildCleanup.paths(project: fixture.path)
    #expect(paths.count == 5)
    #expect(!paths.contains { $0.contains("del") || $0.contains("notes") })
  }

  @Test func trackedOrUnignoredTargetIsRejected() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.git(["init"])
    try fixture.write("Cargo.toml", "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\n")
    try fixture.write("target/debug/incremental/cache", "generated")
    let path = fixture.path + "/target/debug/incremental"
    #expect(throws: (any Error).self) {
      try RustBuildCleanup.validate(path: path, project: fixture.path)
    }
    try fixture.write(".gitignore", "target/\n")
    try CleanerProjectSafety.validateBuild(path: fixture.path + "/target", project: fixture.path)
    try fixture.git(["add", "-f", "target/debug/incremental/cache"])
    #expect(throws: (any Error).self) {
      try RustBuildCleanup.validate(path: path, project: fixture.path)
    }
  }

  @Test func linkedCompilerDirectoryIsRejected() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.git(["init"])
    try fixture.write("Cargo.toml", "[workspace]\n")
    try fixture.write(".gitignore", "target/\n")
    try fixture.write("target/debug/keep", "fixture")
    try fixture.write("source/important", "keep")
    let path = fixture.path + "/target/debug/incremental"
    try FileManager.default.createSymbolicLink(
      atPath: path, withDestinationPath: fixture.path + "/source")
    #expect(throws: CacheCleanError.outsideRoot) {
      try RustBuildCleanup.validate(path: path, project: fixture.path)
    }
  }

  @Test func downloadRulesKeepCredentialsAndRegistrySources() {
    let rules = CleanerCatalog.rules(.packages, home: "/Users/fixture")
    for suffix in [
      "/.cargo/registry/cache", "/Library/Caches/electron", "/Library/Caches/node-gyp",
    ] {
      #expect(
        rules.contains { $0.path.hasSuffix(suffix) && $0.checksRootActivity && !$0.owners.isEmpty })
    }
    #expect(!rules.contains { $0.path.hasSuffix("/.cargo") || $0.path.hasSuffix("/registry/src") })
    #expect(
      CacheCleaner.runtimeTools("node /tools/node-gyp/bin/node-gyp.js rebuild").contains("node-gyp")
    )
  }
}
