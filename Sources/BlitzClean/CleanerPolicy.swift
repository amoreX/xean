import Foundation

enum CleanerCategory: String, CaseIterable, Codable, Sendable, Identifiable {
  case claude, codex, superconductor, editors, packages, browsers, builds, dependencies, docker,
    worktrees, dockerImages, appCaches, pythonEnvironments

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
    case .appCaches: "Other app caches"
    case .pythonEnvironments: "Python environments"
    case .dockerImages: "Unused Docker images"
    case .worktrees: "Old worktrees"
    }
  }

  var detail: String {
    switch self {
    case .claude: "CLI and app caches"
    case .codex: "Desktop caches; sessions stay"
    case .superconductor: "Desktop and web caches"
    case .editors: "Cursor, VS Code, Windsurf, Zed and fed10"
    case .packages: "Package caches and temporary Python environments"
    case .browsers: "Safari, Chrome, Firefox and Zen"
    case .builds: "Build output and stale temporary builds/tests"
    case .dependencies: "Inactive node_modules with a lockfile"
    case .docker: "Unused build cache; containers and volumes stay"
    case .appCaches: "Installed app caches and update downloads"
    case .pythonEnvironments: "Inactive, reproducible environments older than 7 days"
    case .dockerImages: "Unused images older than 24h; local builds may need rebuilding"
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
      ".conductor/workspaces", ".superconductor/worktrees", "Downloads", ".local/share",
      ".codex/experiments", "superconductor/projects",
    ]
    .map { home + "/" + $0 }
  }

  static func staleTestRule(root: String) -> CacheRule {
    .init(
      title: "Stale Tickle test folders", path: root,
      recipe: "Tickle recreates these temporary test fixtures.", owners: [],
      kind: .staleTestDirectory)
  }

  static func rules(_ category: CleanerCategory, home: String) -> [CacheRule] {
    func rule(_ path: String, owners: Set<String>) -> CacheRule {
      .init(
        title: category.title, path: home + "/" + path,
        recipe: "The tool recreates this cache when needed.", owners: owners, kind: .cache,
        checksRootActivity: true)
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
      let owners: Set<String> = ["claude", "Claude", "Claude Helper"]
      return [
        ".claude/cache", "Library/Caches/claude-cli-nodejs",
        "Library/Caches/com.anthropic.claudefordesktop",
      ]
      .map { rule($0, owners: owners) } + electron("Claude", owners: owners)
    case .codex:
      let owners: Set<String> = [
        "Codex", "codex", "Codex Helper", "ChatGPT", "ChatGPT Helper",
      ]
      return ["Library/Caches/Codex", "Library/Caches/com.openai.codex"]
        .map { rule($0, owners: owners) } + electron("Codex", owners: owners)
    case .superconductor:
      let owners: Set<String> = [
        "Superconductor", "superconductor", "Superconductor Helper", "super.engineering",
      ]
      return ["Library/Caches/superconductor", "Library/Caches/com.zarifpour.superconductor"]
        .map { rule($0, owners: owners) } + electron("Superconductor", owners: owners)
    case .editors:
      let owners: Set<String> = ["Cursor", "Code", "Windsurf", "Zed", "zed"]
      return ["Cursor", "Code", "Windsurf"].flatMap { name in
        electron(name, owners: owners)
          + [rule("Library/Application Support/\(name)/CachedData", owners: owners)]
      }
        + ["Library/Caches/cursor-compile-cache", "Library/Caches/Zed"]
        .map { rule($0, owners: owners) }
        + [rule("Library/Caches/fed10", owners: ["fed10", "fed10 Helper"])]
    case .packages:
      return [
        CacheRule(
          title: "Playwright browser downloads", path: home + "/Library/Caches/ms-playwright",
          recipe: "Reinstall with playwright install before running browser tests.",
          owners: ["playwright"],
          kind: .browserDownload, checksRootActivity: true),
        rule(".npm/_cacache", owners: ["npm", "npx", "pnpm"]),
        rule(".npm/_npx", owners: ["npm", "npx"]),
        rule("Library/Caches/Yarn", owners: ["yarn"]),
        rule("Library/Caches/pip", owners: ["pip", "pip3"]),
        rule(".cache/pip", owners: ["pip", "pip3"]),
        rule(".cache/uv", owners: ["uv", "uvx"]),
        rule(".bun/install/cache", owners: ["bun"]),
        rule(".cargo/registry/cache", owners: ["cargo"]),
        rule("Library/Caches/electron", owners: ["npm", "npx", "pnpm", "yarn", "bun", "electron"]),
        rule("Library/Caches/node-gyp", owners: ["node-gyp", "npm", "npx", "pnpm", "yarn", "bun"]),
        rule(".cache/node-gyp", owners: ["node-gyp", "npm", "npx", "pnpm", "yarn", "bun"]),
        rule("Library/Caches/Homebrew/downloads", owners: ["brew"]),
      ]
    case .browsers:
      return SystemDataCatalog.rules(home: home).filter { $0.kind == .cache }
        + [
          rule("Library/Caches/zen", owners: ["zen", "Zen", "Zen Helper"]),
          CacheRule(
            title: "Zen updater cache",
            path: home + "/Library/Caches/Mozilla/updates/Applications/Zen",
            recipe: "Zen downloads updates again.", owners: ["zen", "Zen", "updater"],
            kind: .updaterCache,
            checksRootActivity: true),
        ]
    case .appCaches:
      return electron("Slack", owners: ["Slack", "Slack Helper"])
        + electron("Linear", owners: ["Linear", "Linear Helper"])
        + [
          rule(
            "Library/Application Support/Slack/Service Worker/CacheStorage",
            owners: ["Slack", "Slack Helper"]),
          CacheRule(
            title: "WhatsApp updater cache",
            path: home
              + "/Library/Caches/net.whatsapp.WhatsApp/org.sparkle-project.Sparkle/Installation",
            recipe: "WhatsApp downloads updates again. Messages stay.",
            owners: ["WhatsApp", "Updater", "Autoupdate"], kind: .updaterCache,
            checksRootActivity: true),
        ]
    case .builds:
      var rules = [
        rule(
          "Library/Developer/Xcode/DerivedData",
          owners: ["Xcode", "xcodebuild", "swift", "swift-frontend", "clang"])
      ]
      if home == FileManager.default.homeDirectoryForCurrentUser.path,
        let temporaryRoot = ReviewFile.canonicalPath(FileManager.default.temporaryDirectory.path)
      {
        // Foundation preserves /var here on macOS; validation uses realpath's /private/var.
        rules.append(staleTestRule(root: temporaryRoot))
      }
      return rules
    case .dependencies, .docker, .dockerImages, .worktrees, .pythonEnvironments: return []
    }
  }
}
