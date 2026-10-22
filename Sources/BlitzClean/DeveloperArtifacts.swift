import Darwin
import Foundation

enum DeveloperArtifactKind: String, Sendable {
  case worktree = "Worktrees"
  case dependencies = "Dependencies"
}

struct DeveloperArtifact: Identifiable, Sendable {
  let kind: DeveloperArtifactKind
  let path: String
  let projectPath: String
  let technology: ProjectTechnology
  let bytes: UInt64?
  let modifiedAt: Date?
  let blocker: String?
  let identity: DirectoryIdentity?
  let worktree: WorktreeAssessment?
  let reinstallCommand: String?
  let internalVolume: Bool
  var id: String { path }
  var name: String { URL(fileURLWithPath: projectPath).lastPathComponent }

  func withBlocker(_ reason: String?) -> Self {
    .init(
      kind: kind, path: path, projectPath: projectPath, technology: technology, bytes: bytes,
      modifiedAt: modifiedAt, blocker: reason, identity: identity, worktree: worktree,
      reinstallCommand: reinstallCommand, internalVolume: internalVolume)
  }
}

struct DeveloperDiscovery: Sendable {
  let repositories: [String]
  let dependencies: [String]
  let limited: Bool
  var projects: [String] = []
}

enum DeveloperArtifactScanner {
  static var roots: [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return [
      "\(home)/dev", "\(home)/Developer", "\(home)/Projects", "\(home)/.codex/worktrees",
      "\(home)/.claude/worktrees",
    ]
      + DeveloperLocations.additionalProjectRoots + WorkspacePreferences.load().map(\.directory)
  }

  struct DiscoveryRequest: Sendable {
    let roots: [String]
    var maximumEntries: Int? = nil
    var maximumDepth: Int? = nil
  }

  static func discover(_ request: DiscoveryRequest) -> DeveloperDiscovery {
    var repositories: Set<String> = []
    var dependencies: Set<String> = []
    var projects: Set<String> = []
    var visited: Set<String> = []
    var visitedEntries = 0
    var limited = false
    let ignored: Set<String> = [
      ".git", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".build", ".pnpm",
      ".venv", "Pods", "build", "dist", "target", "Library", ".Trash",
    ]
    for root in Set(request.roots).sorted() {
      guard let path = ReviewFile.canonicalPath(root) else { continue }
      if FileManager.default.fileExists(atPath: path + "/.git") {
        repositories.insert(path)
      }
      var pending: [(String, Int)] = [(path, 0)]
      while let (directoryPath, depth) = pending.popLast() {
        if Task.isCancelled || request.maximumEntries.map({ visitedEntries >= $0 }) == true {
          limited = true
          break
        }
        guard visited.insert(directoryPath).inserted else { continue }
        var info = stat()
        guard lstat(directoryPath, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
          let directory = opendir(directoryPath)
        else {
          limited = true
          continue
        }
        defer { closedir(directory) }
        while true {
          if Task.isCancelled || request.maximumEntries.map({ visitedEntries >= $0 }) == true {
            limited = true
            break
          }
          errno = 0
          guard let entry = readdir(directory) else {
            if errno != 0 { limited = true }
            break
          }
          guard
            let name = withUnsafePointer(
              to: &entry.pointee.d_name,
              { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 1024) {
                  String(validatingCString: $0)
                }
              })
          else {
            limited = true
            continue
          }
          if name == "." || name == ".." { continue }
          visitedEntries += 1
          let child = directoryPath + "/" + name
          var type = entry.pointee.d_type
          if type == DT_UNKNOWN {
            var childInfo = stat()
            guard lstat(child, &childInfo) == 0 else {
              limited = true
              continue
            }
            type = UInt8((childInfo.st_mode & S_IFMT) >> 12)
          }
          if type == DT_LNK { continue }
          if name == ".git" {
            repositories.insert(directoryPath)
          } else if ["package.json", "Cargo.toml", "Package.swift"].contains(name), type != DT_DIR {
            projects.insert(directoryPath)
          } else if type == DT_DIR {
            if name == "node_modules" {
              dependencies.insert(child)
            } else if !ignored.contains(name) {
              // Package metadata is needed only for directories, not every source file.
              guard
                let values = try? URL(fileURLWithPath: child).resourceValues(forKeys: [
                  .isPackageKey
                ])
              else {
                limited = true
                continue
              }
              if values.isPackage == true { continue }
              if let maximumDepth = request.maximumDepth, depth + 1 >= maximumDepth {
                limited = true
              } else {
                pending.append((child, depth + 1))
              }
            }
          }
        }
      }
      if request.maximumEntries.map({ visitedEntries >= $0 }) == true || Task.isCancelled { break }
    }
    return .init(
      repositories: repositories.sorted(), dependencies: dependencies.sorted(),
      limited: limited, projects: projects.sorted())
  }

  struct DependencyRequest: Sendable {
    let path: String
    let activeDirectories: Set<String>?
    let keptDirectories: [String]
  }

  static func dependency(_ input: DependencyRequest) -> DeveloperArtifact {
    let path = input.path
    let context = NodeModulesResolver.resolve(.init(nodeModulesPath: path, fileManager: .default))
    let root =
      context.projectRootPath ?? URL(fileURLWithPath: path).deletingLastPathComponent().path
    let identity = DirectoryIdentity.read(path)
    var blocker: String?
    if identity == nil {
      blocker = "Folder missing or replaced by a link"
    } else if context.origin != .project || context.cleanupTargetPath != path {
      blocker = "Managed cache. Clean it from Storage."
    } else if input.keptDirectories.contains(where: {
      DeveloperPath.contains(.init(path: root, root: $0))
    }) {
      blocker = "Keep running is enabled"
    } else if let active = input.activeDirectories {
      if case .blocked(let reason) = NodeModulesSafety.evaluate(
        .init(
          context: context,
          activeWorkingDirectories: active, fileManager: .default))
      {
        blocker = reason
      }
    } else {
      blocker = "Could not verify running processes"
    }
    let internalVolume = CleanupVolume.read(path)?.isInternal == true
    if blocker == nil, !internalVolume { blocker = "On an external drive. Review it in Finder." }
    let artifact = DeveloperArtifact(
      kind: .dependencies, path: path, projectPath: root,
      technology: ProjectTechnology.detect(.init(directory: root, processName: "node")),
      bytes: DeveloperCommand.bytes(path),
      modifiedAt: try? URL(fileURLWithPath: path).resourceValues(forKeys: [
        .contentModificationDateKey
      ]).contentModificationDate,
      blocker: blocker, identity: identity, worktree: nil,
      reinstallCommand: reinstall(context.lockfilePath), internalVolume: internalVolume)
    return artifact.withBlocker(
      blocker
        ?? DeveloperArtifactCleanup.dependencyBlocker(
          .init(artifact: artifact, active: input.activeDirectories, kept: input.keptDirectories)))
  }

  static func reinstall(_ lockfile: String?) -> String? {
    switch lockfile.map({ URL(fileURLWithPath: $0).lastPathComponent }) {
    case "package-lock.json": "npm ci"
    case "pnpm-lock.yaml": "pnpm install --frozen-lockfile"
    case "yarn.lock": "yarn install --frozen-lockfile"
    case "bun.lock", "bun.lockb": "bun install --frozen-lockfile"
    default: nil
    }
  }
}
