import CryptoKit
import Darwin
import Foundation

enum CleanupDataKind: Sendable {
  case cache
  case discoveredAppCache
  case diagnosticReport
  case temporaryEnvironment, temporaryBuild
  case staleTestDirectory
  case pythonEnvironment, browserDownload, updaterCache

  var alwaysRequiresAge: Bool {
    self == .discoveredAppCache || self == .staleTestDirectory || self == .temporaryEnvironment
      || self == .temporaryBuild
      || self == .pythonEnvironment || self == .browserDownload || self == .updaterCache
  }

  var minimumAgeDays: Int {
    self == .diagnosticReport
      ? 30 : self == .pythonEnvironment || self == .discoveredAppCache ? 7 : 1
  }
}

struct CacheRule: Sendable {
  let title: String
  let path: String
  let recipe: String
  let owners: Set<String>
  let kind: CleanupDataKind
  var checksRootActivity = false
  var entryName: String? = nil
  var owningApp: String? = nil

  static var standard: [Self] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return [
      .init(
        title: "npm downloads", path: home + "/.npm/_cacache",
        recipe: "npm downloads packages again when needed.", owners: ["npm", "pnpm", "npx"],
        kind: .cache),
      .init(
        title: "Homebrew downloads", path: home + "/Library/Caches/Homebrew/downloads",
        recipe: "Homebrew downloads installers again when needed.", owners: ["brew", "ruby"],
        kind: .cache),
      .init(
        title: "pip cache", path: home + "/Library/Caches/pip",
        recipe: "pip downloads and builds packages again.", owners: ["pip", "pip3"], kind: .cache),
      .init(
        title: "pip downloads", path: home + "/.cache/pip",
        recipe: "pip downloads and builds packages again.", owners: ["pip", "pip3"], kind: .cache),
      .init(
        title: "Yarn cache", path: home + "/Library/Caches/Yarn",
        recipe: "Yarn downloads packages again.", owners: ["yarn"], kind: .cache),
      .init(
        title: "Xcode build data", path: home + "/Library/Developer/Xcode/DerivedData",
        recipe: "Xcode rebuilds indexes and intermediates. The next build takes longer.",
        owners: ["Xcode", "xcodebuild", "swift", "swift-frontend", "clang"], kind: .cache),
    ] + SystemDataCatalog.rules(home: home)
  }

  func accepts(_ path: String) -> Bool {
    if let entryName, URL(fileURLWithPath: path).lastPathComponent != entryName { return false }
    if kind == .pythonEnvironment {
      return PythonEnvironmentCleanup.isReproducible(path)
    }
    if kind == .browserDownload {
      let name = URL(fileURLWithPath: path).lastPathComponent
      return ["chromium-", "chromium_headless_shell-", "firefox-", "webkit-", "ffmpeg-"].contains {
        let suffix = name.dropFirst($0.count)
        return name.hasPrefix($0) && !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
      }
    }
    if kind == .temporaryEnvironment || kind == .temporaryBuild {
      return TemporaryCleanup.kind(at: path) == kind
    }
    if kind == .staleTestDirectory {
      let name = URL(fileURLWithPath: path).lastPathComponent
      let prefix = "tickle-desktop-test-"
      let suffix = name.dropFirst(prefix.count)
      var info = stat()
      return name.hasPrefix(prefix) && suffix.count == 6
        && suffix.utf8.allSatisfy {
          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
        && lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
        && info.st_uid == getuid()
    }
    guard kind == .diagnosticReport else { return true }
    var info = stat()
    return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
      && ["ips", "crash", "diag", "hang", "spin"].contains(
        URL(fileURLWithPath: path).pathExtension.lowercased())
  }
}

struct CacheTree: Equatable, Sendable {
  let fingerprint: String
  let bytes: UInt64
  let newest: Date
}

struct CacheCandidate: Identifiable, Sendable {
  let path: String
  let rule: CacheRule
  let tree: CacheTree
  var id: String { path }
  var name: String { URL(fileURLWithPath: path).lastPathComponent }
  var displayName: String {
    let parts = name.split(separator: "--", maxSplits: 1)
    if parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(\.isHexDigit) {
      return String(parts[1])
    }
    return name
  }
}

struct CacheScanRequest: Sendable {
  let rules: [CacheRule]
  let date: Date
  var respectsAge = true
}

struct CacheScanResult: Sendable {
  let candidates: [CacheCandidate]
  let notes: [String]
}

enum CacheCleanError: LocalizedError {
  case outsideRoot, linkedRoot, specialFile, changed, recent, busy, unverified
  var errorDescription: String? {
    switch self {
    case .outsideRoot: "This folder is outside an allowed cleanup location."
    case .linkedRoot: "This folder is a symbolic link. Its destination is kept."
    case .specialFile: "This folder contains a socket, device or another unsupported file type."
    case .changed: "This cache changed after the scan. Scan again to review it."
    case .recent: "This item is too recent for this cleanup rule. It stays on your Mac."
    case .busy: "A process is using this cache or its package manager. Close it and scan again."
    case .unverified: "Activity or disk checks could not be completed. This cache was kept."
    }
  }
}

enum CacheCleaner {
  struct TreeRequest {
    let path: String
  }

  static func tree(_ request: TreeRequest) throws -> CacheTree {
    // Keep only pending paths; completed entries do not accumulate in memory.
    var pending = [request.path]
    var bytes: UInt64 = 0
    var newest = Date.distantPast
    var hasher = SHA256()
    while let path = pending.popLast() {
      try Task.checkCancellation()
      var info = stat()
      guard lstat(path, &info) == 0 else { throw CacheCleanError.unverified }
      guard info.st_uid == getuid() else { throw CacheCleanError.unverified }
      let type = info.st_mode & S_IFMT
      if type == S_IFLNK, path == request.path { throw CacheCleanError.linkedRoot }
      guard type == S_IFREG || type == S_IFDIR || type == S_IFLNK else {
        throw CacheCleanError.specialFile
      }
      bytes += UInt64(max(0, info.st_blocks)) * 512
      newest = max(newest, Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)))
      let identity =
        "\(path)|\(info.st_dev)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)|\(info.st_mode)\n"
      hasher.update(data: Data(identity.utf8))
      if type == S_IFLNK {
        // Fingerprint the link itself; never traverse or count its destination.
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: path)
        hasher.update(data: Data((destination + "\n").utf8))
      }
      if type == S_IFDIR {
        guard let directory = opendir(path) else { throw CacheCleanError.unverified }
        defer { closedir(directory) }
        var children: [String] = []
        while true {
          try Task.checkCancellation()
          errno = 0
          guard let entry = readdir(directory) else {
            guard errno == 0 else { throw CacheCleanError.unverified }
            break
          }
          let name = withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1024) {
              String(validatingCString: $0)
            }
          }
          guard let name else { throw CacheCleanError.unverified }
          if name != ".", name != ".." { children.append(name) }
        }
        // Sorted depth-first traversal keeps scan and pre-delete fingerprints identical.
        for child in children.sorted().reversed() { pending.append(path + "/" + child) }
      }
    }
    return CacheTree(
      fingerprint: hasher.finalize().map { String(format: "%02x", $0) }.joined(), bytes: bytes,
      newest: newest)
  }

  static func validateLocation(_ candidate: CacheCandidate) throws {
    let root = candidate.rule.path
    guard ReviewFile.canonicalPath(root) == root,
      ReviewFile.canonicalPath(candidate.path) == candidate.path,
      URL(fileURLWithPath: candidate.path).deletingLastPathComponent().path == root,
      candidate.rule.accepts(candidate.path),
      CleanupVolume.read(candidate.path)?.isInternal == true
    else { throw CacheCleanError.outsideRoot }
  }

  static func processes() throws -> Set<String> {
    let result = CleanupActivity.runCommand(
      .init(executable: "/bin/ps", arguments: ["-axo", "comm="], timeout: 5))
    guard result.status == 0, !result.output.isEmpty else { throw CacheCleanError.unverified }
    var names = Set(
      result.output.split(separator: "\n").map {
        URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).lastPathComponent
      })
    // Package-manager entry points can run under generic interpreter executable names.
    let commands = CleanupActivity.runCommand(
      .init(executable: "/bin/ps", arguments: ["-axo", "args="], timeout: 5))
    guard commands.status == 0, !commands.output.isEmpty else { throw CacheCleanError.unverified }
    for line in commands.output.split(separator: "\n") {
      names.formUnion(runtimeTools(String(line)))
    }
    return names
  }

  static func runtimeTools(_ command: String) -> Set<String> {
    let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let executable = tokens.first.map({ URL(fileURLWithPath: $0).lastPathComponent }),
      ["node", "python", "python3", "ruby"].contains(executable)
        || executable.hasPrefix("python3.")
    else { return [] }
    let entryPoints: [String: String] = [
      "node-gyp.js": "node-gyp", "npm-cli.js": "npm", "npx-cli.js": "npx", "pnpm.cjs": "pnpm",
      "pnpm.js": "pnpm",
      "yarn.js": "yarn", "yarn.cjs": "yarn", "pip": "pip", "pip3": "pip3",
      "uv": "uv", "uvx": "uvx", "brew.rb": "brew",
    ]
    var tools: Set<String> = []
    for token in tokens.dropFirst() {
      if let tool = entryPoints[URL(fileURLWithPath: token).lastPathComponent] {
        tools.insert(tool)
      }
    }
    return tools
  }

  static func scan(_ request: CacheScanRequest) -> CacheScanResult {
    var candidates: [CacheCandidate] = []
    var notes: [String] = []
    guard let owners = try? processes() else {
      return .init(candidates: [], notes: [CacheCleanError.unverified.localizedDescription])
    }
    for rule in request.rules {
      guard FileManager.default.fileExists(atPath: rule.path) else { continue }
      guard !Task.isCancelled else { break }
      if rule.kind == .discoveredAppCache {
        do { try AppCacheDiscovery.validate(rule) } catch {
          notes.append("\(rule.path): \(error.localizedDescription)")
          continue
        }
      }
      guard owners.isDisjoint(with: rule.owners) else {
        notes.append(
          "\(rule.title) (\(rule.path)): app or package manager is running; kept. Close it and scan again."
        )
        continue
      }
      guard ReviewFile.canonicalPath(rule.path) == rule.path,
        let children = try? FileManager.default.contentsOfDirectory(atPath: rule.path)
      else {
        notes.append("\(rule.title) (\(rule.path)): folder could not be read or is a link.")
        continue
      }
      if rule.checksRootActivity {
        do { try validateInactive(rule.path) } catch {
          notes.append("\(rule.title) (\(rule.path)): \(error.localizedDescription)")
          continue
        }
      }
      var recentTestFolders = 0
      for child in children.sorted() where rule.entryName == nil || child == rule.entryName {
        guard !Task.isCancelled else { break }
        let path = rule.path + "/" + child
        guard rule.accepts(path) else { continue }
        do {
          var rootInfo = stat()
          let cutoff = request.date.addingTimeInterval(-Double(rule.kind.minimumAgeDays) * 86_400)
          if request.respectsAge || rule.kind.alwaysRequiresAge,
            lstat(path, &rootInfo) == 0, rootInfo.st_uid == getuid(),
            rootInfo.st_mode & S_IFMT == S_IFDIR || rootInfo.st_mode & S_IFMT == S_IFREG,
            Date(timeIntervalSince1970: Double(rootInfo.st_mtimespec.tv_sec)) >= cutoff
          {
            // The tree's newest date includes its root. A recent root already fails age policy.
            if rule.kind == .staleTestDirectory {
              recentTestFolders += 1
            } else if rule.kind.alwaysRequiresAge {
              notes.append(
                "\(child): kept until every file is at least \(rule.kind.minimumAgeDays * 24) hours old."
              )
            }
            continue
          }
          if rule.kind == .temporaryEnvironment || rule.kind == .temporaryBuild
            || rule.kind == .browserDownload
            || rule.kind == .updaterCache
          {
            try TemporaryCleanup.validateActivity(at: path)
          }
          if rule.kind == .pythonEnvironment { try PythonEnvironmentCleanup.validateActivity(path) }
          let contents = try tree(.init(path: path))
          let candidate = CacheCandidate(path: path, rule: rule, tree: contents)
          try validateLocation(candidate)
          guard
            (!request.respectsAge && !rule.kind.alwaysRequiresAge)
              || contents.newest
                < request.date.addingTimeInterval(-Double(rule.kind.minimumAgeDays) * 86_400),
            contents.bytes > 0
          else {
            if rule.kind == .staleTestDirectory {
              recentTestFolders += 1
            } else if rule.kind.alwaysRequiresAge {
              notes.append(
                "\(child): kept until every file is at least \(rule.kind.minimumAgeDays * 24) hours old."
              )
            }
            continue
          }
          if rule.kind == .temporaryBuild, let workspace = TemporaryCleanup.workspace(at: path) {
            try CleanerProjectSafety.validateActivity(workspace)
          }
          candidates.append(candidate)
        } catch {
          notes.append("\(rule.title) / \(child): \(error.localizedDescription)")
        }
      }
      if recentTestFolders > 0 {
        notes.append("\(recentTestFolders) recent Tickle test folders kept (24-hour minimum).")
      }
    }
    return .init(candidates: candidates.sorted { $0.tree.bytes > $1.tree.bytes }, notes: notes)
  }

  static func validateInactive(_ path: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      throw CacheCleanError.unverified
    }
    let activity = CleanupActivity.command(
      isDirectory.boolValue ? ["-nP", "+D", path] : ["-nP", "--", path])
    if activity.status == 0 { throw CacheCleanError.busy }
    guard activity.status == 1, activity.output.isEmpty else { throw CacheCleanError.unverified }
  }

  static func delete(_ candidate: CacheCandidate, respectsAge: Bool = true) throws -> CleanupWin {
    try validateLocation(candidate)
    if candidate.rule.kind == .discoveredAppCache { try AppCacheDiscovery.validate(candidate.rule) }
    let owners = try processes()
    guard owners.isDisjoint(with: candidate.rule.owners) else { throw CacheCleanError.busy }
    if candidate.rule.checksRootActivity { try validateInactive(candidate.rule.path) }
    try validateInactive(candidate.path)
    if candidate.rule.kind == .temporaryEnvironment || candidate.rule.kind == .temporaryBuild
      || candidate.rule.kind == .browserDownload
      || candidate.rule.kind == .updaterCache
    {
      try TemporaryCleanup.validateActivity(at: candidate.path)
    }
    if candidate.rule.kind == .temporaryBuild,
      let workspace = TemporaryCleanup.workspace(at: candidate.path)
    {
      try CleanerProjectSafety.validateActivity(workspace)
    }
    if candidate.rule.kind == .pythonEnvironment {
      try PythonEnvironmentCleanup.validateActivity(candidate.path)
    }
    let current = try tree(.init(path: candidate.path))
    guard current == candidate.tree else { throw CacheCleanError.changed }
    guard
      (!respectsAge && !candidate.rule.kind.alwaysRequiresAge)
        || current.newest
          < Date.now.addingTimeInterval(-Double(candidate.rule.kind.minimumAgeDays) * 86_400)
    else {
      throw CacheCleanError.recent
    }
    try validateLocation(candidate)
    let before = CleanupVolume.read(candidate.path)
    try FileManager.default.removeItem(atPath: candidate.path)
    return .init(
      id: UUID().uuidString, date: .now, title: "Cleaned \(candidate.rule.title)",
      paths: [candidate.path],
      before: before, after: before.flatMap { CleanupVolume.read($0.path) }, bytes: current.bytes)
  }
}

protocol QuickCleanDriver: Sendable {
  func scan() async -> CacheScanResult
  func delete(_ candidate: CacheCandidate) async throws -> CleanupWin
}

struct NativeQuickCleanDriver: QuickCleanDriver {
  func scan() async -> CacheScanResult {
    await Task.detached(priority: .utility) {
      CacheCleaner.scan(.init(rules: CacheRule.standard, date: .now))
    }.value
  }

  func delete(_ candidate: CacheCandidate) async throws -> CleanupWin {
    try await Task.detached(priority: .utility) { try CacheCleaner.delete(candidate) }.value
  }
}

struct QuickCleanResult: Equatable {
  let removedCount: Int
  let skippedCount: Int
  let removedBytes: UInt64
  let availableGain: UInt64?
}

@MainActor
final class QuickCleanModel: ObservableObject {
  private let driver: any QuickCleanDriver
  private var scanNotes: [String] = []
  @Published private(set) var candidates: [CacheCandidate] = []
  @Published private(set) var notes: [String] = []
  @Published private(set) var isScanning = false
  @Published private(set) var isCleaning = false
  @Published private(set) var scannedAt: Date?
  @Published private(set) var status: String?
  @Published private(set) var completed = 0
  @Published private(set) var total = 0
  @Published private(set) var activeTitle: String?
  @Published private(set) var result: QuickCleanResult?
  @Published var selected: Set<String> = []

  init(driver: any QuickCleanDriver = NativeQuickCleanDriver()) {
    self.driver = driver
  }

  var isBusy: Bool { isScanning || isCleaning }
  var quickCandidates: [CacheCandidate] { candidates.filter { $0.rule.kind == .cache } }
  var quickBytes: UInt64 { quickCandidates.reduce(0) { $0 + $1.tree.bytes } }
  var canClean: Bool { !isBusy && scannedAt != nil && result == nil && !quickCandidates.isEmpty }

  var selectedItems: [CacheCandidate] {
    selected.isEmpty ? [] : candidates.filter { selected.contains($0.path) }
  }
  var selectedBytes: UInt64 {
    candidates.reduce(0) { selected.contains($1.path) ? $0 + $1.tree.bytes : $0 }
  }
  var totalBytes: UInt64 { candidates.reduce(0) { $0 + $1.tree.bytes } }

  func scan() {
    guard !isScanning, !isCleaning else { return }
    isScanning = true
    result = nil
    status = nil
    Task {
      let result = await driver.scan()
      candidates = result.candidates
      scanNotes = result.notes
      notes = result.notes
      selected.formIntersection(candidates.map(\.path))
      scannedAt = .now
      isScanning = false
    }
  }

  func cleanAll(history: CleanupOverviewModel) {
    guard canClean else { return }
    selected = Set(quickCandidates.map(\.path))
    clean(history: history)
  }

  func clean(history: CleanupOverviewModel) {
    guard !isCleaning, !isScanning, !selectedItems.isEmpty else { return }
    let items = selectedItems
    isCleaning = true
    completed = 0
    total = items.count
    result = nil
    activeTitle = nil
    status = "Checking activity before cleanup…"
    Task {
      var failures: [String] = []
      var removed: Set<String> = []
      var removedBytes: UInt64 = 0
      let preservedScanNotes = scanNotes
      let before = CleanupVolume.read(FileManager.default.homeDirectoryForCurrentUser.path)
      for item in items {
        activeTitle = item.rule.title
        do {
          let win = try await driver.delete(item)
          history.record(win)
          removed.insert(item.path)
          removedBytes += item.tree.bytes
        } catch {
          failures.append("\(item.rule.title) / \(item.name): \(error.localizedDescription)")
        }
        completed += 1
        status = "Reviewed \(completed) of \(items.count) items"
      }
      let after = before.flatMap { CleanupVolume.read($0.path) }
      let gain = before.flatMap { old in
        after.map { $0.available > old.available ? $0.available - old.available : 0 }
      }
      candidates.removeAll { removed.contains($0.path) }
      selected.subtract(removed)
      notes = failures + preservedScanNotes
      result = .init(
        removedCount: removed.count, skippedCount: failures.count,
        removedBytes: removedBytes, availableGain: gain)
      status =
        "Cleaned \(removed.count) items · \(gain.map(ByteText.full) ?? "unmeasured") more disk space available.\(failures.isEmpty ? "" : " \(failures.count) kept; see details.") Other disk activity affects this measurement."
      isCleaning = false
      activeTitle = nil
    }
  }
}
