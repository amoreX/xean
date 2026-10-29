import Foundation

/// Discover only conventional cache locations belonging to an installed, identifiable app.
enum AppCacheDiscovery {
  struct App {
    let path: String
    let identifier: String
    let executable: String
    let names: Set<String>
  }

  static func normalized(_ name: String) -> String {
    name.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  static func app(at path: String) -> App? {
    guard ReviewFile.canonicalPath(path) == path,
      let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist"),
      let identifier = info["CFBundleIdentifier"] as? String,
      !identifier.hasPrefix("com.apple."),
      let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty
    else { return nil }
    let names = [
      URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
      info["CFBundleName"] as? String ?? "", info["CFBundleDisplayName"] as? String ?? "",
      executable,
    ].map(normalized).filter { !$0.isEmpty }
    return App(path: path, identifier: identifier, executable: executable, names: Set(names))
  }

  static func installed(in roots: [String]) -> [App] {
    var result: [App] = []
    for root in roots {
      guard let entries = FileManager.default.enumerator(atPath: root) else { continue }
      while let entry = entries.nextObject() as? String {
        if Task.isCancelled { return result }
        if entry.hasSuffix(".app") {
          entries.skipDescendants()
          if let value = app(at: root + "/" + entry) { result.append(value) }
        }
      }
    }
    return result
  }

  static func owner(name: String, apps: [App]) -> App? {
    let key = normalized(name)
    var aliases = Set([key])
    if name.hasSuffix("-updater") {
      let base = normalized(String(name.dropLast("-updater".count)))
      aliases.insert(base)
      if base.hasSuffix("desktop") { aliases.insert(String(base.dropLast(7))) }
    }
    let matches = apps.filter {
      name == $0.identifier || !aliases.isDisjoint(with: $0.names)
    }
    let paths = Set(matches.map(\.path))
    return paths.count == 1 ? matches.first : nil
  }

  static func discover(home: String, apps: [App], excluding: [String]) -> (
    rules: [CacheRule], notes: [String]
  ) {
    var rules: [CacheRule] = []
    var notes: [String] = []
    func add(_ path: String, owner: App) {
      guard
        !excluding.contains(where: {
          path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/")
        }), ReviewFile.canonicalPath(path) == path
      else { return }
      rules.append(
        .init(
          title: "App cache", path: path,
          recipe: "The app recreates its cache.",
          owners: [owner.executable],
          kind: .discoveredAppCache, checksRootActivity: true, owningApp: owner.path))
    }
    let cacheRoot = home + "/Library/Caches"
    for name in (try? FileManager.default.contentsOfDirectory(atPath: cacheRoot)) ?? [] {
      let path = cacheRoot + "/" + name
      if let owner = owner(name: name, apps: apps) {
        add(path, owner: owner)
      } else if !name.hasPrefix("com.apple."),
        !excluding.contains(where: { $0 == path || $0.hasPrefix(path + "/") })
      {
        notes.append(
          "\(path): kept because an installed app could not be identified unambiguously.")
      }
    }
    let support = home + "/Library/Application Support"
    for name in (try? FileManager.default.contentsOfDirectory(atPath: support)) ?? [] {
      guard let owner = owner(name: name, apps: apps) else { continue }
      for leaf in [
        "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GraphiteDawnCache", "GPUPersistentCache",
      ] {
        let path = support + "/" + name + "/" + leaf
        if FileManager.default.fileExists(atPath: path) { add(path, owner: owner) }
      }
    }
    return (rules, notes)
  }

  static func validate(_ rule: CacheRule) throws {
    guard let path = rule.owningApp, let owner = app(at: path),
      rule.owners.contains(owner.executable)
    else {
      throw CacheCleanError.unverified
    }
    let processes = CleanupActivity.runCommand(
      .init(executable: "/bin/ps", arguments: ["-axo", "comm="], timeout: 5))
    guard processes.status == 0, !processes.output.isEmpty else { throw CacheCleanError.unverified }
    guard
      !processes.output.split(separator: "\n").contains(where: {
        let executable = $0.trimmingCharacters(in: .whitespaces)
        return executable.hasPrefix(path + "/") || executable.hasPrefix(rule.path + "/")
      })
    else { throw CacheCleanError.busy }
  }
}
