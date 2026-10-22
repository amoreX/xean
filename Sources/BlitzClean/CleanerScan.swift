import Foundation

enum CleanerTarget: Sendable {
  case cache(CacheCandidate)
  case build(CacheCandidate, project: String)
  case artifact(DeveloperArtifact, tree: CacheTree)
  case docker
  case dockerImages
}

struct CleanerItem: Identifiable, Sendable {
  let category: CleanerCategory
  let path: String
  let bytes: UInt64
  let target: CleanerTarget
  var id: String { category.rawValue + ":" + path }
  var name: String { URL(fileURLWithPath: path).lastPathComponent }
  var branch: String? {
    guard case .artifact(let artifact, _) = target else { return nil }
    return artifact.worktree?.record.branch?.replacingOccurrences(of: "refs/heads/", with: "")
  }
}

struct CleanerKeptItem: Identifiable, Sendable {
  let category: CleanerCategory
  let path: String
  let reason: String
  var bytes: UInt64? = nil
  var id: String { category.rawValue + ":" + path }
  var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct CleanerScan: Sendable {
  static let minimumVisibleBytes: UInt64 = 50_000_000
  var items: [CleanerItem] = []
  var kept: [CleanerKeptItem] = []
  var notes: [String] = []
  var categoryNotes: [CleanerCategory: [String]] = [:]
  var scannedAt = Date.now

  var inventorySummary: String? {
    let small = items.filter { $0.bytes < Self.minimumVisibleBytes }
    if !small.isEmpty {
      let bytes = small.reduce(UInt64(0)) { $0 + $1.bytes }
      return
        "\(small.count) smaller \(small.count == 1 ? "item" : "items") · \(ByteText.compact(bytes)) included in Clean."
    }
    if items.isEmpty && kept.isEmpty {
      return notes.isEmpty
        ? "No eligible data in the supported locations." : "Some locations were skipped."
    }
    return nil
  }

  var visibleItems: [CleanerItem] { items.filter { $0.bytes >= Self.minimumVisibleBytes } }
  var visibleKept: [CleanerKeptItem] {
    kept.filter { $0.bytes == nil || ($0.bytes ?? 0) >= Self.minimumVisibleBytes }
  }
}

protocol CleanerDriver: Sendable {
  func scan(_ preferences: CleanerPreferences, automatic: Bool) async -> CleanerScan
  func remove(_ item: CleanerItem, preferences: CleanerPreferences, automatic: Bool) async throws
    -> CleanupWin
  func availableBytes() async -> UInt64?
}

struct NativeCleanerDriver: CleanerDriver {
  func scan(_ preferences: CleanerPreferences, automatic: Bool = true) async -> CleanerScan {
    let scan = Task.detached(priority: .utility) {
      CleanerScanner.scan(preferences, automatic: automatic)
    }
    return await withTaskCancellationHandler {
      await scan.value
    } onCancel: {
      scan.cancel()
    }
  }

  func availableBytes() async -> UInt64? {
    await Task.detached(priority: .utility) {
      CleanupVolume.read(FileManager.default.homeDirectoryForCurrentUser.path)?.available
    }.value
  }

  func remove(_ item: CleanerItem, preferences: CleanerPreferences, automatic: Bool = true)
    async throws -> CleanupWin
  {
    try await Task.detached(priority: .utility) {
      guard preferences.categories.contains(item.category) else { throw CacheCleanError.unverified }
      switch item.target {
      case .cache(let cache): return try CacheCleaner.delete(cache, respectsAge: automatic)
      case .build(let cache, let project):
        try CleanerProjectSafety.validateBuild(path: cache.path, project: project)
        try CleanerProjectSafety.validateActivity(project)
        return try CacheCleaner.delete(cache, respectsAge: automatic)
      case .artifact(let artifact, let expected):
        let tree = try CacheCleaner.tree(.init(path: artifact.path))
        guard tree == expected else { throw CacheCleanError.changed }
        if automatic {
          let days = artifact.kind == .worktree ? preferences.worktreeDays : 7
          try CleanerProjectSafety.validateAge(
            path: artifact.path, tree: tree, days: days,
            worktree: artifact.kind == .worktree)
        }
        let outcome = DeveloperArtifactCleanup.remove(artifact)
        guard outcome.removed, var win = outcome.win else {
          throw CleanerError.kept(outcome.message)
        }
        win.bytes = item.bytes
        return win
      case .dockerImages:
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let before = CleanupVolume.read(home)
        _ = try DockerStorageService().cleanUnusedImages()
        return .init(
          id: UUID().uuidString, date: .now, title: "Cleaned unused Docker images",
          paths: ["docker://local/images"], before: before, after: CleanupVolume.read(home))
      case .docker:
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let before = CleanupVolume.read(home)
        _ = try DockerStorageService().cleanBuildCache(
          minimumAgeDays: automatic ? CleanupDataKind.cache.minimumAgeDays : nil)
        return .init(
          id: UUID().uuidString, date: .now, title: "Cleaned Docker build cache",
          paths: ["docker://local/build-cache"], before: before, after: CleanupVolume.read(home))
      }
    }.value
  }
}

enum CleanerError: LocalizedError {
  case kept(String)
  var errorDescription: String? {
    switch self {
    case .kept(let reason): reason
    }
  }
}

enum CleanerScanner {
  static func scan(_ preferences: CleanerPreferences, automatic: Bool) -> CleanerScan {
    let preferences = preferences.normalized
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var result = CleanerScan()
    let protectedLocations: [(CleanerCategory, String, String)] = [
      (.codex, home + "/.codex/sessions", "Conversation history is kept; it is not an app cache."),
      (
        .codex, home + "/.codex/packages",
        "Installed Codex runtimes are kept; they may still be required."
      ),
      (
        .builds, home + "/Library/Developer/CoreSimulator",
        "Simulator apps and device data are kept. Review unused devices in Xcode."
      ),
      (
        .builds, home + "/Library/Developer/Xcode/iOS DeviceSupport",
        "Physical-device debugging support is kept. Review it in Xcode."
      ),
    ]
    for (category, path, reason) in protectedLocations
    where preferences.categories.contains(category) && FileManager.default.fileExists(atPath: path)
    {
      result.kept.append(.init(category: category, path: path, reason: reason))
    }
    var rules = CleanerCategory.allCases.filter(preferences.categories.contains).flatMap {
      category in CleanerCatalog.rules(category, home: home).map { (category, $0) }
    }
    if !preferences.categories.isDisjoint(with: [.packages, .builds, .claude]) {
      let roots = Array(
        Set(
          [FileManager.default.temporaryDirectory.path, "/private/tmp"].compactMap(
            ReviewFile.canonicalPath)))
      let temporary = TemporaryCleanup.discover(roots: roots, categories: preferences.categories)
      rules += temporary.rules
      result.kept += temporary.kept
    }
    for category in CleanerCategory.allCases where preferences.categories.contains(category) {
      let caches = CacheCleaner.scan(
        .init(rules: rules.filter { $0.0 == category }.map(\.1), date: .now, respectsAge: automatic)
      )
      result.notes += caches.notes
      result.categoryNotes[category] = caches.notes
      for candidate in caches.candidates {
        result.items.append(
          .init(
            category: category, path: candidate.path, bytes: candidate.tree.bytes,
            target: .cache(candidate)))
      }
    }

    if !preferences.categories.isDisjoint(with: [.worktrees, .builds, .dependencies]) {
      let roots =
        CleanerCatalog.roots(home: home) + preferences.projectRoots
        + DeveloperLocations.additionalProjectRoots + WorkspacePreferences.load().map(\.directory)
      let previousNoteCount = result.notes.count
      scanProjects(roots: roots, preferences: preferences, automatic: automatic, result: &result)
      for category in preferences.categories.intersection([.worktrees, .builds, .dependencies]) {
        result.categoryNotes[category, default: []] += result.notes.dropFirst(previousNoteCount)
      }
    }
    if !preferences.categories.isDisjoint(with: [.docker, .dockerImages]) {
      do {
        let snapshot = try DockerStorageService().load()
        if preferences.categories.contains(.dockerImages),
          let images = snapshot.categories.first(where: { $0.id == "images" }),
          images.reclaimableBytes > 0
        {
          result.items.append(
            .init(
              category: .dockerImages, path: "docker://local/images",
              bytes: images.reclaimableBytes, target: .dockerImages))
          let note =
            "Docker image size is an upper estimate. Only images older than 24 hours and unused by any container are removed; tagged local images can be removed too."
          result.notes.append(note)
          result.categoryNotes[.dockerImages, default: []].append(note)
        }
        if preferences.categories.contains(.docker),
          let cache = snapshot.categories.first(where: { $0.id == "build-cache" }),
          cache.reclaimableBytes > 0
        {
          result.items.append(
            .init(
              category: .docker, path: "docker://local/build-cache",
              bytes: cache.reclaimableBytes, target: .docker))
          if automatic {
            result.notes.append(
              "Docker size is an upper estimate; only unused build cache older than 24 hours is removed."
            )
          }
        }
      } catch {
        let note = "Docker: " + error.localizedDescription
        result.notes.append(note)
        for category in preferences.categories.intersection([.docker, .dockerImages]) {
          result.categoryNotes[category, default: []].append(note)
        }
      }
    }
    // Manual results feed separate category caches; combine them into a removal plan later.
    consolidate(&result, excludingOverlaps: automatic)
    result.scannedAt = .now
    return result
  }

  static func consolidate(_ result: inout CleanerScan, excludingOverlaps: Bool = true) {
    // A worktree may itself contain another candidate. Never schedule overlapping removals.
    let worktrees = result.items.filter { $0.category == .worktrees }.map(\.path)
    result.items.removeAll { item in
      excludingOverlaps && item.category != .worktrees
        && worktrees.contains { item.path.hasPrefix($0 + "/") }
    }
    var seen: Set<String> = []
    result.items = result.items.filter { seen.insert($0.path).inserted }.sorted {
      $0.bytes > $1.bytes
    }
    var seenNotes: Set<String> = []
    var seenKept: Set<String> = []
    result.kept = result.kept.filter { seenKept.insert($0.id).inserted }.sorted {
      $0.path < $1.path
    }
    result.notes = Array(result.notes.filter { seenNotes.insert($0).inserted }.prefix(150))
  }

  static func scanProjects(
    roots: [String], preferences: CleanerPreferences, automatic: Bool, result: inout CleanerScan
  ) {
    let discovery = DeveloperArtifactScanner.discover(
      .init(roots: roots))
    if discovery.limited {
      result.notes.append(
        "Some project folders could not be read, or the scan was interrupted."
      )
    }
    let active = CleanupActivity.workingDirectories()
    let kept = WorkspacePreferences.load().filter(\.keepRunning).map(\.directory)
    var repositories: Set<String> = []
    if preferences.categories.contains(.worktrees) {
      for repository in discovery.repositories {
        guard !Task.isCancelled else { return }
        guard let records = GitWorktrees.list(repository), let primary = records.first?.path,
          repositories.insert(primary).inserted
        else { continue }
        // The primary checkout belongs in the inventory, but it is never a removal candidate.
        result.kept.append(.init(category: .worktrees, path: primary, reason: "Primary checkout"))
        let base = GitWorktrees.base(repository)
        for record in records.dropFirst() {
          guard !Task.isCancelled else { return }
          let assessment = GitWorktrees.inspect(
            .init(
              repository: repository, record: record,
              base: base, activeDirectories: active, keptDirectories: kept)
          )
          if let blocker = assessment.blocker {
            result.kept.append(.init(category: .worktrees, path: record.path, reason: blocker))
            result.notes.append(
              "\(URL(fileURLWithPath: record.path).lastPathComponent): \(blocker)")
            continue
          }
          do {
            let tree = try CacheCleaner.tree(.init(path: record.path))
            if automatic {
              try CleanerProjectSafety.validateAge(
                path: record.path, tree: tree,
                days: preferences.worktreeDays, worktree: true)
            }
            guard CleanupVolume.read(record.path)?.isInternal == true else {
              throw CacheCleanError.outsideRoot
            }
            let artifact = DeveloperArtifact(
              kind: .worktree, path: record.path, projectPath: record.path,
              technology: .detect(.init(directory: record.path, processName: "")),
              bytes: tree.bytes,
              modifiedAt: tree.newest, blocker: nil, identity: assessment.identity,
              worktree: assessment,
              reinstallCommand: nil, internalVolume: true)
            result.items.append(
              .init(
                category: .worktrees, path: record.path, bytes: tree.bytes,
                target: .artifact(artifact, tree: tree)))
          } catch {
            result.kept.append(
              .init(category: .worktrees, path: record.path, reason: error.localizedDescription))
            result.notes.append("\(record.path): \(error.localizedDescription)")
          }
        }
      }
    }
    if preferences.categories.contains(.dependencies) {
      for path in discovery.dependencies {
        guard !Task.isCancelled else { return }
        let artifact = DeveloperArtifactScanner.dependency(
          .init(path: path, activeDirectories: active, keptDirectories: kept))
        if let blocker = artifact.blocker {
          result.kept.append(
            .init(category: .dependencies, path: path, reason: blocker, bytes: artifact.bytes))
          result.notes.append("\(path): \(blocker)")
          continue
        }
        do {
          let tree = try CacheCleaner.tree(.init(path: path))
          if automatic {
            try CleanerProjectSafety.validateAge(path: path, tree: tree, days: 7, worktree: false)
          }
          result.items.append(
            .init(
              category: .dependencies, path: path, bytes: tree.bytes,
              target: .artifact(artifact, tree: tree)))
        } catch {
          result.kept.append(
            .init(
              category: .dependencies, path: path, reason: error.localizedDescription,
              bytes: artifact.bytes))
          result.notes.append("\(path): \(error.localizedDescription)")
        }
      }
    }
    if preferences.categories.contains(.builds) {
      for project in Set(discovery.projects + discovery.repositories).sorted() {
        guard !Task.isCancelled else { return }
        for name in CleanerProjectSafety.buildNames(project: project) {
          let path = project + "/" + name
          guard FileManager.default.fileExists(atPath: path) else { continue }
          do {
            try CleanerProjectSafety.validateBuild(path: path, project: project)
            try CleanerProjectSafety.validateActivity(project, active: active)
            let tree = try CacheCleaner.tree(.init(path: path))
            if automatic {
              try CleanerProjectSafety.validateAge(
                path: path, tree: tree, days: CleanupDataKind.cache.minimumAgeDays, worktree: false)
            }
            let rule = CacheRule(
              title: "Build files", path: project, recipe: "Rebuild the project.",
              // Project activity is checked above and again at deletion; unrelated tools are safe.
              owners: [],
              kind: .cache)
            let candidate = CacheCandidate(path: path, rule: rule, tree: tree)
            try CacheCleaner.validateLocation(candidate)
            result.items.append(
              .init(
                category: .builds, path: path, bytes: tree.bytes,
                target: .build(candidate, project: project)))
          } catch {
            result.kept.append(
              .init(category: .builds, path: path, reason: error.localizedDescription))
            result.notes.append("\(path): \(error.localizedDescription)")
          }
        }
      }
    }
    // Protected folders are already ineligible. Do not walk entire simulators,
    // primary checkouts or runtime stores merely to display their size.
  }
}

enum CleanerProjectSafety {
  static func buildNames(project: String) -> [String] {
    func has(_ name: String) -> Bool {
      FileManager.default.fileExists(atPath: project + "/" + name)
    }
    var names: [String] = []
    if has("package.json") {
      names += [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", "dist", "build"]
    }
    if has("Cargo.toml") { names.append("target") }
    if has("Package.swift") { names.append(".build") }
    return names
  }

  static func validateBuild(path: String, project: String) throws {
    let name = URL(fileURLWithPath: path).lastPathComponent
    guard URL(fileURLWithPath: path).deletingLastPathComponent().path == project,
      buildNames(project: project).contains(name), DirectoryIdentity.read(path) != nil
    else {
      throw CacheCleanError.outsideRoot
    }
    let tracked = DeveloperCommand.git(
      .init(directory: project, arguments: ["ls-files", "-z", "--", name]))
    let ignored = DeveloperCommand.git(
      .init(directory: project, arguments: ["check-ignore", "-q", "--", name]))
    guard tracked.status == 0, tracked.output.isEmpty, ignored.status == 0 else {
      throw CleanerError.kept("Build output must be ignored by Git and contain no tracked files.")
    }
  }

  static func validateActivity(
    _ project: String, active: Set<String>? = CleanupActivity.workingDirectories()
  ) throws {
    guard let active else { throw CacheCleanError.unverified }
    let kept = WorkspacePreferences.load().filter(\.keepRunning).map(\.directory)
    guard !active.contains(where: { DeveloperPath.contains(.init(path: $0, root: project)) }),
      !kept.contains(where: { DeveloperPath.contains(.init(path: project, root: $0)) })
    else {
      throw CacheCleanError.busy
    }
  }

  static func validateAge(
    path: String, tree: CacheTree, days: Int, worktree: Bool, now: Date = .now
  ) throws {
    var newest = tree.newest
    if let created = try URL(fileURLWithPath: path).resourceValues(forKeys: [.creationDateKey])
      .creationDate
    {
      newest = max(newest, created)
    }
    if worktree {
      let gitDir = DeveloperCommand.git(
        .init(directory: path, arguments: ["rev-parse", "--absolute-git-dir"]))
      guard gitDir.status == 0 else { throw CacheCleanError.unverified }
      let metadata = try CacheCleaner.tree(
        .init(
          path: gitDir.output.trimmingCharacters(in: .whitespacesAndNewlines)))
      newest = max(newest, metadata.newest)
    }
    guard newest < now.addingTimeInterval(-Double(max(1, days)) * 86_400) else {
      throw CacheCleanError.recent
    }
  }
}

/// Three independent filesystem removals may run together. Shared Git/Docker state is exclusive.
struct CleanerDeletionResult: Sendable {
  let item: CleanerItem
  let win: CleanupWin?
  let failure: String?

  static func canStart(_ item: CleanerItem, alongside active: [CleanerItem]) -> Bool {
    func exclusive(_ item: CleanerItem) -> Bool {
      switch item.target {
      case .docker, .dockerImages: return true
      case .artifact(let artifact, _): return artifact.kind == .worktree
      default: return false
      }
    }
    func scope(_ item: CleanerItem) -> String {
      switch item.target {
      case .build(_, let project): return project
      case .artifact(let artifact, _): return artifact.projectPath
      default: return item.path
      }
    }
    func overlaps(_ first: String, _ second: String) -> Bool {
      let a = URL(fileURLWithPath: first).standardizedFileURL.path
      let b = URL(fileURLWithPath: second).standardizedFileURL.path
      return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
    return active.allSatisfy {
      !exclusive(item) && !exclusive($0)
        && !overlaps(item.path, $0.path) && !overlaps(scope(item), scope($0))
    }
  }
}
