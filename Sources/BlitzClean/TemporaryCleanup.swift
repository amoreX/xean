import Darwin
import Foundation

/// Only generated environments/build directories are eligible; arbitrary temporary projects stay.
enum TemporaryCleanup {
  static func kind(at path: String) -> CleanupDataKind? {
    guard ReviewFile.canonicalPath(path) == path,
      let children = try? FileManager.default.contentsOfDirectory(atPath: path)
    else { return nil }
    let names = Set(children)
    if names.contains("pyvenv.cfg"), names.contains("bin"), names.contains("lib"),
      names.isSubset(of: [
        "pyvenv.cfg", "bin", "lib", "lib64", "include", "share", ".gitignore", ".lock",
        "CACHEDIR.TAG",
      ]),
      let data = marker(path + "/pyvenv.cfg"),
      let config = String(data: data, encoding: .utf8),
      config.split(separator: "\n").contains(where: { $0.hasPrefix("home =") })
    {
      return .temporaryEnvironment
    }
    if names.contains("Build"),
      names.isSubset(of: [
        "Build", "Index.noindex", "Logs", "ModuleCache.noindex", "CompilationCache.noindex",
        "SDKExplicitPrecompiledModules", "SDKStatCaches.noindex", "info.plist",
        "SymbolCache.noindex", "TextIndex.noindex", "TestResults",
      ]),
      workspace(at: path) != nil
    {
      return .temporaryBuild
    }
    return nil
  }

  private static func marker(_ path: String) -> Data? {
    var info = stat()
    guard ReviewFile.canonicalPath(path) == path, lstat(path, &info) == 0,
      info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_size <= 65_536
    else { return nil }
    return FileManager.default.contents(atPath: path)
  }

  static func workspace(at path: String) -> String? {
    guard let data = marker(path + "/info.plist"),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let workspace = plist["WorkspacePath"] as? String, workspace.hasPrefix("/"),
      ["xcworkspace", "xcodeproj"].contains(URL(fileURLWithPath: workspace).pathExtension)
    else { return nil }
    return URL(fileURLWithPath: workspace).deletingLastPathComponent().path
  }

  static func commandReferences(_ command: String, directory: String) -> Bool {
    func normalized(_ value: String) -> String {
      value.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        .replacingOccurrences(of: "/private/var/", with: "/var/")
    }
    return normalized(command).contains(normalized(directory) + "/")
  }

  static func validateActivity(at path: String) throws {
    // Python can close imported files while still relying on the environment for later imports.
    let processes = CleanupActivity.runCommand(
      .init(executable: "/bin/ps", arguments: ["-axo", "comm=,args="], timeout: 5))
    guard processes.status == 0, !processes.output.isEmpty else { throw CacheCleanError.unverified }
    if commandReferences(processes.output, directory: path) { throw CacheCleanError.busy }
  }

  static func discover(roots: [String], categories: Set<CleanerCategory>) -> (
    rules: [(CleanerCategory, CacheRule)], kept: [CleanerKeptItem]
  ) {
    var rules: [(CleanerCategory, CacheRule)] = []
    var kept: [CleanerKeptItem] = []
    var pending = roots
    var seen: Set<String> = []
    while let path = pending.popLast() {
      if Task.isCancelled { break }
      var info = stat()
      guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
        roots.contains(path) || info.st_uid == getuid()
      else { continue }
      guard seen.insert(path).inserted, ReviewFile.canonicalPath(path) == path else { continue }
      if path.contains("/claude-\(getuid())/"),
        URL(fileURLWithPath: path).lastPathComponent == "scratchpad"
      {
        if categories.contains(.claude) {
          kept.append(
            .init(
              category: .claude, path: path,
              reason:
                "Claude scratchpad may contain source files and unsaved work. Review it manually; it is not a disposable cache.",
              bytes: try? CacheCleaner.tree(.init(path: path)).bytes))
        }
        continue
      }
      if let kind = kind(at: path) {
        let category: CleanerCategory = kind == .temporaryEnvironment ? .packages : .builds
        if categories.contains(category) {
          let url = URL(fileURLWithPath: path)
          rules.append(
            (
              category,
              CacheRule(
                title: kind == .temporaryEnvironment
                  ? "Temporary Python environment" : "Temporary Xcode build",
                path: url.deletingLastPathComponent().path,
                recipe: "Recreated by the development tool.",
                owners: kind == .temporaryEnvironment
                  ? ["uv", "uvx", "pip", "pip3"] : ["xcodebuild"],
                kind: kind, entryName: url.lastPathComponent)
            ))
        }
        continue
      }
      guard let children = try? FileManager.default.contentsOfDirectory(atPath: path),
        !children.contains(".git")
      else { continue }
      if children.contains("pyvenv.cfg") {
        if categories.contains(.packages) {
          kept.append(
            .init(
              category: .packages, path: path,
              reason:
                "This temporary environment contains extra files or unverified metadata. Review it manually."
            ))
        }
        continue
      }
      let excluded: Set<String> = ["node_modules", ".git", "Build", "lib", "bin", "Library"]
      for child in children where !excluded.contains(child) {
        pending.append(path + "/" + child)
      }
    }
    return (rules, kept)
  }
}
