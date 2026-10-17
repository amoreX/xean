import AppKit
import SwiftUI
import Testing

@testable import BlitzClean

@MainActor
struct CleanerRenderTests {
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
      to: directory.appendingPathComponent("cleaner-completed.png"))
    try await render(
      view, size: .init(width: 380, height: 500),
      to: directory.appendingPathComponent("cleaner-completed-compact.png"))
    try await Task.sleep(for: .milliseconds(5_400))
    #expect(model.status.isEmpty)
    try await render(
      view, size: .init(width: 420, height: 592),
      to: directory.appendingPathComponent("cleaner-completed-dismissed.png"))
  }

  private func render(_ view: some View, size: CGSize, to url: URL) async throws {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(300))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    window.orderOut(nil)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
  }
}
