import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BlitzClean

struct CleanerTraversalTests {
  @Test func preservesFoundationFingerprintForHiddenUnicodeAndNestedEntries() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    for name in [
      "z-last", ".hidden", "A", "folder/z", "folder/.nested", "folder/café-🌲",
      "folder/a\u{0308}", "é-first", "line\nbreak", "pipe|name",
    ] {
      try fixture.write("cache/" + name, name)
    }
    try fixture.write("outside/keep", String(repeating: "x", count: 8192))
    let root = fixture.path + "/cache"
    try FileManager.default.createDirectory(
      atPath: root + "/empty", withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: root + "/link", withDestinationPath: "../outside")

    // The Foundation traversal defines the fingerprint order used before optimization.
    var paths: [String] = []
    func collect(_ path: String) throws {
      paths.append(path)
      var info = stat()
      try #require(lstat(path, &info) == 0)
      if info.st_mode & S_IFMT == S_IFDIR {
        for name in try FileManager.default.contentsOfDirectory(atPath: path).sorted() {
          try collect(path + "/" + name)
        }
      }
    }
    try collect(root)
    var digest = SHA256()
    var bytes: UInt64 = 0
    var newest = Date.distantPast
    for path in paths {
      var info = stat()
      try #require(lstat(path, &info) == 0)
      bytes += UInt64(info.st_blocks) * 512
      newest = max(newest, Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)))
      digest.update(
        data: Data(
          "\(path)|\(info.st_dev)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)|\(info.st_mode)\n"
            .utf8))
      if info.st_mode & S_IFMT == S_IFLNK {
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: path)
        digest.update(data: Data((target + "\n").utf8))
      }
    }
    let expected = CacheTree(
      fingerprint: digest.finalize().map { String(format: "%02x", $0) }.joined(),
      bytes: bytes, newest: newest)
    #expect(try CacheCleaner.tree(.init(path: root)) == expected)
  }

  @Test func unreadableDirectoryRejectsTheEntireTree() throws {
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    try fixture.write("cache/blocked/keep", "unreadable data must stay")
    let path = fixture.path + "/cache/blocked"
    try #require(chmod(path, 0) == 0)
    defer { chmod(path, 0o700) }
    #expect(throws: CacheCleanError.unverified) {
      try CacheCleaner.tree(.init(path: fixture.path + "/cache"))
    }
    #expect(FileManager.default.fileExists(atPath: path))
  }
}
