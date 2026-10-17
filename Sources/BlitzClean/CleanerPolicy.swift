import Foundation

enum CleanerCategory: String, CaseIterable, Codable, Sendable, Identifiable {
  case claude, codex, superconductor, editors, packages, browsers, builds, dependencies, docker,
    worktrees

  var id: String { rawValue }
  var title: String {
    switch self {
    case .claude: "Claude Code"
    case .codex: "Codex"
    case .superconductor: "Superconductor"
    case .editors: "Coding editors"
    case .packages: "Package caches"
    case .browsers: "Browser caches"
    case .builds: "Build files"
    case .dependencies: "Project dependencies"
    case .docker: "Docker build cache"
    case .worktrees: "Old worktrees"
    }
  }

  var detail: String {
    switch self {
    case .claude: "CLI and app caches"
    case .codex: "Desktop caches; sessions stay"
    case .superconductor: "Desktop and web caches"
    case .editors: "Cursor, VS Code, Windsurf and Zed"
    case .packages: "npm, Yarn, pip, uv, Bun and Homebrew"
    case .browsers: "Safari, Chrome and Firefox"
    case .builds: "Xcode, Swift, Rust and web build output"
    case .dependencies: "Inactive node_modules with a lockfile"
    case .docker: "Unused build cache; containers and volumes stay"
    case .worktrees: "Clean, merged, inactive Git worktrees"
    }
  }
}

enum CleanerMode: String, CaseIterable, Codable, Sendable {
  case manual, notify, automatic
  var title: String {
    switch self {
    case .manual: "Manual"
    case .notify: "Low-space warning"
    case .automatic: "Auto-clean"
    }
  }
}

struct CleanerPreferences: Codable, Equatable, Sendable {
  var mode: CleanerMode = .manual
  var notifyWhileAutomatic = false
  var freeSpaceGB = 20
  var automaticFreeSpaceGB = 20
  var checkMinutes: Int { 25 }
  var worktreeDays = 30
  var categories: Set<CleanerCategory> = [
    .claude, .codex, .superconductor, .editors, .packages, .builds,
  ]
  var projectRoots: [String] = []

  static let key = "cleaner.preferences.v1"

  var warningsEnabled: Bool {
    get { mode == .notify || (mode == .automatic && notifyWhileAutomatic) }
    set {
      if mode == .automatic {
        notifyWhileAutomatic = newValue
      } else {
        mode = newValue ? .notify : .manual
      }
    }
  }

  mutating func setAutomatic(_ enabled: Bool) {
    if enabled {
      notifyWhileAutomatic = warningsEnabled
      mode = .automatic
    } else {
      mode = notifyWhileAutomatic ? .notify : .manual
      notifyWhileAutomatic = false
    }
  }

  private enum CodingKeys: String, CodingKey {
    case mode, notifyWhileAutomatic, freeSpaceGB, automaticFreeSpaceGB, worktreeDays, categories,
      projectRoots
  }

  init() {}

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    mode = try values.decodeIfPresent(CleanerMode.self, forKey: .mode) ?? .manual
    notifyWhileAutomatic =
      try values.decodeIfPresent(Bool.self, forKey: .notifyWhileAutomatic) ?? false
    freeSpaceGB = try values.decodeIfPresent(Int.self, forKey: .freeSpaceGB) ?? 20
    automaticFreeSpaceGB =
      try values.decodeIfPresent(Int.self, forKey: .automaticFreeSpaceGB) ?? freeSpaceGB
    worktreeDays = try values.decodeIfPresent(Int.self, forKey: .worktreeDays) ?? 30
    categories =
      try values.decodeIfPresent(Set<CleanerCategory>.self, forKey: .categories) ?? categories
    projectRoots = try values.decodeIfPresent([String].self, forKey: .projectRoots) ?? []
  }

  var normalized: Self {
    var value = self
    value.freeSpaceGB = min(1_000, max(1, freeSpaceGB))
    value.automaticFreeSpaceGB = min(1_000, max(1, automaticFreeSpaceGB))
    value.worktreeDays = min(365, max(1, worktreeDays))
    value.projectRoots = Array(Set(projectRoots.filter { $0.hasPrefix("/") })).sorted()
    return value
  }

  func isBelowThreshold(_ available: UInt64?, automatic: Bool = false) -> Bool {
    guard let available else { return false }
    let limit = automatic ? normalized.automaticFreeSpaceGB : normalized.freeSpaceGB
    return available < UInt64(limit) * 1_000_000_000
  }

  static func load(_ defaults: UserDefaults) -> Self {
    guard let data = defaults.data(forKey: key),
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return .init() }
    return value.normalized
  }

  func save(_ defaults: UserDefaults) {
    if let data = try? JSONEncoder().encode(normalized) { defaults.set(data, forKey: Self.key) }
  }
}

enum CleanerCatalog {
  static func roots(home: String) -> [String] {
    [
      "dev", "Developer", "Projects", "Code", "Documents/GitHub", "Documents/ChatGPT",
      ".codex/worktrees", ".claude/worktrees", ".cursor/worktrees", "conductor/workspaces",
      ".conductor/workspaces", ".superconductor/worktrees",
    ]
    .map { home + "/" + $0 }
  }

  static func rules(_ category: CleanerCategory, home: String) -> [CacheRule] {
    func rule(_ path: String, owners: Set<String>) -> CacheRule {
      .init(
        title: category.title, path: home + "/" + path,
        recipe: "The tool recreates this cache when needed.", owners: owners, kind: .cache)
    }
    func electron(_ name: String, owners: Set<String>) -> [CacheRule] {
      [
        "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GraphiteDawnCache", "GPUPersistentCache",
      ]
      .map { rule("Library/Application Support/" + name + "/" + $0, owners: owners) }
    }
    switch category {
    case .claude:
      let owners: Set<String> = ["claude", "Claude", "Claude Helper", "node"]
      return [
        ".claude/cache", "Library/Caches/claude-cli-nodejs",
        "Library/Caches/com.anthropic.claudefordesktop",
      ]
      .map { rule($0, owners: owners) } + electron("Claude", owners: owners)
    case .codex:
      let owners: Set<String> = [
        "Codex", "codex", "Codex Helper", "ChatGPT", "ChatGPT Helper", "node",
      ]
      return ["Library/Caches/Codex", "Library/Caches/com.openai.codex"]
        .map { rule($0, owners: owners) } + electron("Codex", owners: owners)
    case .superconductor:
      let owners: Set<String> = [
        "Superconductor", "superconductor", "Superconductor Helper", "super.engineering", "node",
      ]
      return ["Library/Caches/superconductor", "Library/Caches/com.zarifpour.superconductor"]
        .map { rule($0, owners: owners) } + electron("Superconductor", owners: owners)
    case .editors:
      let owners: Set<String> = ["Cursor", "Code", "Windsurf", "Zed", "zed", "node"]
      return ["Cursor", "Code", "Windsurf"].flatMap { name in
        electron(name, owners: owners)
          + [rule("Library/Application Support/\(name)/CachedData", owners: owners)]
      }
        + ["Library/Caches/cursor-compile-cache", "Library/Caches/Zed"]
        .map { rule($0, owners: owners) }
    case .packages:
      return [
        rule(".npm/_cacache", owners: ["npm", "npx", "node", "pnpm"]),
        rule("Library/Caches/Yarn", owners: ["yarn", "node"]),
        rule("Library/Caches/pip", owners: ["pip", "pip3", "python", "python3"]),
        rule(".cache/pip", owners: ["pip", "pip3", "python", "python3"]),
        rule(".cache/uv", owners: ["uv", "uvx", "python", "python3"]),
        rule(".bun/install/cache", owners: ["bun"]),
        rule("Library/Caches/Homebrew/downloads", owners: ["brew", "ruby"]),
      ]
    case .browsers:
      return SystemDataCatalog.rules(home: home).filter { $0.kind == .cache }
    case .builds:
      return [
        rule(
          "Library/Developer/Xcode/DerivedData",
          owners: ["Xcode", "xcodebuild", "swift", "swift-frontend", "clang"])
      ]
    case .dependencies, .docker, .worktrees: return []
    }
  }
}
