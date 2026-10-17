import Foundation

@main
enum BlitzCleanEntry {
  @MainActor
  static func main() {
    guard !CommandLine.arguments.contains("--purge-memory") else {
      return
    }
    BrandMigration.run()
    BlitzCleanApp.main()
  }
}
