import Darwin
import Foundation

/// Project environments require reproducible dependencies, inactivity and a seven-day age floor.
enum PythonEnvironmentCleanup {
  static func isReproducible(_ path: String) -> Bool {
    guard TemporaryCleanup.kind(at: path) == .temporaryEnvironment else { return false }
    let project = URL(fileURLWithPath: path).deletingLastPathComponent().path
    return ["requirements.txt", "requirements-dev.txt", "uv.lock", "poetry.lock", "Pipfile.lock"]
      .contains {
        let manifest = project + "/" + $0
        var info = stat()
        return ReviewFile.canonicalPath(manifest) == manifest && lstat(manifest, &info) == 0
          && info.st_mode & S_IFMT == S_IFREG && info.st_uid == getuid() && info.st_size > 0
      }
  }

  static func rule(_ path: String) -> CacheRule {
    let url = URL(fileURLWithPath: path)
    return .init(
      title: "Python environment", path: url.deletingLastPathComponent().path,
      recipe: "Recreate the environment from the project's dependency manifest.",
      owners: ["uv", "uvx", "pip", "pip3", "poetry", "pipenv"], kind: .pythonEnvironment,
      entryName: url.lastPathComponent)
  }

  static func validateActivity(_ path: String) throws {
    try TemporaryCleanup.validateActivity(at: path)
    let project = URL(fileURLWithPath: path).deletingLastPathComponent().path
    try CleanerProjectSafety.validateActivity(project)
    var ancestor = URL(fileURLWithPath: project)
    while ancestor.path != "/" {
      if FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) {
        let tracked = DeveloperCommand.git(
          .init(directory: project, arguments: ["ls-files", "-z", "--", path]))
        let ignored = DeveloperCommand.git(
          .init(directory: project, arguments: ["check-ignore", "-q", "--", path]))
        guard tracked.status == 0, tracked.output.isEmpty, ignored.status == 0 else {
          throw CleanerError.kept(
            "Python environments in Git projects must be ignored and contain no tracked files.")
        }
        break
      }
      ancestor.deleteLastPathComponent()
    }
  }
}
