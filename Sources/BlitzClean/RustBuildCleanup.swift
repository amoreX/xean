import Foundation

/// Keep Cargo's runnable outputs; only offer known compiler-generated subdirectories.
enum RustBuildCleanup {
  static let names: Set<String> = ["incremental", "deps", "build", "examples", ".fingerprint"]
  static let tools: Set<String> = ["cargo", "rustc", "rustdoc"]

  static func paths(project: String) -> [String] {
    ["debug", "release"].flatMap { profile in
      names.sorted().map { project + "/target/" + profile + "/" + $0 }
    }.filter { FileManager.default.fileExists(atPath: $0) }
  }

  static func validate(path: String, project: String) throws {
    try CleanerProjectSafety.validateBuild(path: project + "/target", project: project)
    guard paths(project: project).contains(path), ReviewFile.canonicalPath(path) == path else {
      throw CacheCleanError.outsideRoot
    }
    let kept = WorkspacePreferences.load().filter(\.keepRunning).map(\.directory)
    guard !kept.contains(where: { DeveloperPath.contains(.init(path: project, root: $0)) }) else {
      throw CacheCleanError.busy
    }
    guard try CacheCleaner.processes().isDisjoint(with: tools) else { throw CacheCleanError.busy }
    // A running app outside this subtree is safe; loaded libraries or binaries inside it are not.
    try CacheCleaner.validateInactive(path)
  }

  static func scan(project: String, automatic: Bool, result: inout CleanerScan) {
    for path in paths(project: project) {
      guard !Task.isCancelled else { return }
      do {
        try validate(path: path, project: project)
        let tree = try CacheCleaner.tree(.init(path: path))
        if automatic {
          try CleanerProjectSafety.validateAge(path: path, tree: tree, days: 1, worktree: false)
        }
        let rule = CacheRule(
          title: "Rust build files",
          path: URL(fileURLWithPath: path).deletingLastPathComponent().path,
          recipe: "Cargo rebuilds compiler artifacts; app bundles stay.", owners: tools,
          kind: .cache)
        let candidate = CacheCandidate(path: path, rule: rule, tree: tree)
        try CacheCleaner.validateLocation(candidate)
        result.items.append(
          .init(
            category: .builds, path: path, bytes: tree.bytes,
            target: .rustBuild(candidate, project: project)))
      } catch {
        result.kept.append(.init(category: .builds, path: path, reason: error.localizedDescription))
        result.notes.append("\(path): \(error.localizedDescription)")
      }
    }
  }
}
