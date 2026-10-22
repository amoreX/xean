import AppKit
import SwiftUI
import Testing

@testable import BlitzClean

@MainActor
struct CleanerRenderTests {
  @Test func rendersSkippedLocationsAndSmallItemsWhenRequested() async throws {
    guard let output = ProcessInfo.processInfo.environment["BLITZCLEAN_DESIGN_DIR"] else { return }
    let directory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let defaults = try #require(UserDefaults(suiteName: "coverage-render-\(UUID())"))
    let model = CleanerModel(
      defaults: defaults, driver: FixtureCleanerDriver(),
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    let report = CleanerScan(
      items: [
        .init(category: .codex, path: "/Example/cache/small", bytes: 12_000_000, target: .docker)
      ],
      kept: [
        .init(
          category: .codex, path: "/Example/.codex/sessions",
          reason: "Conversation history is kept; it is not an app cache.")
      ],
      notes: [
        "Codex (~/Library/Caches/com.openai.codex): app or package manager is running; kept. Close it and scan again."
      ])
    try await render(
      CleanerInventoryList(model: model, report: report).padding(18),
      size: .init(width: 380, height: 350),
      to: directory.appendingPathComponent("coverage-notes.png"))
  }

  @Test func rendersCleanerDialogWhenRequested() async throws {
    guard let output = ProcessInfo.processInfo.environment["BLITZCLEAN_DESIGN_DIR"] else { return }
    let directory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let defaults = try #require(UserDefaults(suiteName: "cleaner-render-\(UUID())"))
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let model = CleanerModel(
      defaults: defaults, driver: FixtureCleanerDriver(),
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    let view = CleanerView(
      model: model, launchAtLogin: LaunchAtLoginController(),
      menuBarStats: CleanerMenuBarStats(defaults: defaults))
    try await render(
      view, size: .init(width: 420, height: 592),
      to: directory.appendingPathComponent("cleaner-manual.png"))
    model.preferences.categories = Set(CleanerCategory.allCases)
    model.preferences.mode = .automatic
    try await render(
      view, size: .init(width: 380, height: 500),
      to: directory.appendingPathComponent("cleaner-compact.png"))
    await model.scanNow()
    try await render(
      view, size: .init(width: 420, height: 592),
      to: directory.appendingPathComponent("cleaner-scanned.png"))
    model.preferences.mode = .manual
    await model.cleanSelected()
    try await render(
      view, size: .init(width: 420, height: 592),
      to: directory.appendingPathComponent("cleaner-completed.png"), settle: 2_400)
    try await render(
      view, size: .init(width: 380, height: 500),
      to: directory.appendingPathComponent("cleaner-completed-compact.png"), settle: 2_400)
    try await Task.sleep(for: .milliseconds(5_400))
    #expect(model.status.isEmpty)
    try await render(
      view, size: .init(width: 420, height: 592),
      to: directory.appendingPathComponent("cleaner-completed-dismissed.png"), settle: 2_400)
  }

  @Test func rendersImmediateRemovalWhenRequested() async throws {
    guard let output = ProcessInfo.processInfo.environment["BLITZCLEAN_DESIGN_DIR"] else { return }
    let directory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let defaults = try #require(UserDefaults(suiteName: "cleaner-removal-render-\(UUID())"))
    let fixture = try CleanerFixture()
    defer { fixture.remove() }
    let driver = FixtureCleanerDriver()
    await driver.setScanPaths(["/Example/agent-auth/.next", "/Example/agent-settings/node_modules"])
    let model = CleanerModel(
      defaults: defaults, driver: driver,
      history: .init(url: URL(fileURLWithPath: fixture.path + "/history.json")))
    let view = CleanerView(
      model: model, launchAtLogin: LaunchAtLoginController(),
      menuBarStats: CleanerMenuBarStats(defaults: defaults))
    let host = NSHostingView(
      rootView: view.frame(width: 420, height: 580).background(
        Color(nsColor: .windowBackgroundColor)))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 580)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))
    await model.cleanSelected()
    // Completion must appear without waiting for a per-row animation queue.
    #expect(await driver.removals.count == 2)
    try await Task.sleep(for: .milliseconds(50))
    try snapshot(host, to: directory.appendingPathComponent("cleaner-removal-immediate.png"))
  }

  private func render(_ view: some View, size: CGSize, to url: URL, settle: Int = 300) async throws
  {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor)))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(settle))
    try snapshot(host, to: url)
    window.orderOut(nil)
  }

  private func snapshot(_ host: NSView, to url: URL) throws {
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
  }
}
