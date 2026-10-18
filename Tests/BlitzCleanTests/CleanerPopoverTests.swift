import AppKit
import SwiftUI
import Testing

@testable import BlitzClean

@MainActor
struct CleanerPopoverTests {
  @Test func clearBackdropPreservesContentGlassAndFullWindowOpacity() async throws {
    guard #available(macOS 26.0, *) else { return }
    let source = NSWindow(
      contentRect: NSRect(x: 200, y: 200, width: 500, height: 400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let anchor = try #require(source.contentView)
    source.orderFrontRegardless()
    let controlGlass = NSGlassEffectView()
    controlGlass.style = .regular
    controlGlass.tintColor = .systemBlue
    let controller = NSViewController()
    controller.view = controlGlass
    let popover = CleanerPopover()
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 200, height: 100)
    defer {
      popover.close()
      source.orderOut(nil)
    }

    for _ in 0..<2 {
      popover.present(relativeTo: NSRect(x: 200, y: 350, width: 24, height: 24), of: anchor)
      try await Task.sleep(for: .milliseconds(250))
      popover.resize(to: NSSize(width: 200, height: 64), animated: false)
      let frame = try #require(popover.window?.contentView?.superview)
      func backdrops(in view: NSView) -> [NSGlassEffectView] {
        if view === controlGlass { return [] }
        if let glass = view as? NSGlassEffectView { return [glass] }
        return view.subviews.flatMap { backdrops(in: $0) }
      }
      let glass = try #require(backdrops(in: frame).first)
      let clear =
        !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
      #expect(glass.style == (clear ? .clear : .regular))
      #expect(controlGlass.style == .regular)
      #expect(controlGlass.tintColor == .systemBlue)
      #expect(controlGlass.alphaValue == 1)
      #expect(popover.window?.alphaValue == 1)
      popover.close()
    }
  }

  @Test func reopeningDuringDismissalKeepsTheNativePopoverVisible() async throws {
    let window = NSWindow(
      contentRect: NSRect(x: 200, y: 200, width: 500, height: 400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let anchor = NSView(frame: NSRect(x: 200, y: 350, width: 24, height: 24))
    window.contentView?.addSubview(anchor)
    window.orderFrontRegardless()
    let popover = CleanerPopover()
    var dismissals = 0
    popover.didDismiss = { dismissals += 1 }
    popover.behavior = .applicationDefined
    popover.contentViewController = NSHostingController(rootView: Text("Fixture"))
    popover.contentSize = NSSize(width: 200, height: 100)
    defer {
      popover.close()
      window.orderOut(nil)
    }
    #expect(!popover.isShown)
    popover.present(relativeTo: anchor.bounds, of: anchor)
    popover.dismissAnimated()
    popover.present(relativeTo: anchor.bounds, of: anchor)
    try await Task.sleep(for: .milliseconds(250))
    #expect(dismissals == 0)
    #expect(popover.isPresented)
    #expect(popover.isShown)
    #expect(popover.window?.alphaValue == 1)
    popover.dismissAnimated()
    try await Task.sleep(for: .milliseconds(250))
    #expect(!popover.isShown)
    #expect(dismissals == 1)
  }

  @Test func statsWidthChangesKeepTheEraserAndPopoverAtTheSameScreenPosition() async throws {
    let screen = try #require(NSScreen.main).visibleFrame
    let right = screen.midX + 100
    let window = NSWindow(
      contentRect: NSRect(x: right - 240, y: screen.maxY - 40, width: 240, height: 24),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let button = try #require(window.contentView)
    let anchor = CleanerStatusAnchor(in: button, trailingInset: 3)
    window.orderFrontRegardless()
    button.layoutSubtreeIfNeeded()
    let popover = CleanerPopover()
    let controller = NSHostingController(
      rootView: Text("Stats anchor fixture").frame(width: 200, height: 100))
    controller.sizingOptions = []
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 200, height: 100)
    defer {
      popover.close()
      window.orderOut(nil)
    }
    popover.present(relativeTo: anchor.bounds, of: anchor)
    try await Task.sleep(for: .milliseconds(250))
    let originalFrame = try #require(popover.window).frame
    let originalAnchor = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    #expect(anchor.bounds.width == 18)
    #expect(abs(originalAnchor.midX - (right - 12)) < 0.5)
    #expect(abs(originalFrame.midX - originalAnchor.midX) < 0.5)
    #expect(anchor.hitTest(.zero) == nil)

    for width: CGFloat in [120, 24, 160, 320, 240] {
      window.setFrame(
        NSRect(x: right - width, y: window.frame.minY, width: width, height: 24), display: true)
      button.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(60))
      let anchorOnScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
      let frame = try #require(popover.window).frame
      #expect(abs(anchorOnScreen.midX - originalAnchor.midX) < 0.5)
      #expect(abs(frame.midX - originalFrame.midX) < 0.5)
      #expect(abs(frame.maxY - originalFrame.maxY) < 0.5)
      #expect(popover.positioningRect == anchor.bounds)
    }
  }

  @Test func anOpenPopoverStaysPutDuringSeparateMenuBarLayoutUpdates() async throws {
    let screen = try #require(NSScreen.main).visibleFrame
    let window = NSWindow(
      contentRect: NSRect(x: screen.midX - 140, y: screen.maxY - 40, width: 240, height: 24),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let button = try #require(window.contentView)
    let anchor = CleanerStatusAnchor(in: button, trailingInset: 3)
    window.orderFrontRegardless()
    button.layoutSubtreeIfNeeded()
    let popover = CleanerPopover()
    let controller = NSHostingController(
      rootView: Text("Stationary panel fixture").frame(width: 200, height: 100))
    controller.sizingOptions = []
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 200, height: 100)
    defer {
      popover.close()
      window.orderOut(nil)
    }
    popover.present(relativeTo: anchor.bounds, of: anchor)
    try await Task.sleep(for: .milliseconds(250))
    let originalFrame = try #require(popover.window).frame
    let originalSourceFrame = window.frame

    // The menu bar need not update a status window's origin and width atomically.
    window.setFrameOrigin(NSPoint(x: window.frame.minX + 90, y: window.frame.minY))
    try await Task.sleep(for: .milliseconds(60))
    #expect(try #require(popover.window).frame == originalFrame)
    window.setContentSize(NSSize(width: 150, height: 24))
    button.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(60))
    #expect(try #require(popover.window).frame == originalFrame)

    // Also keep the open panel still if a neighboring status item shifts the eraser.
    window.setFrameOrigin(NSPoint(x: originalSourceFrame.minX - 50, y: window.frame.minY - 8))
    try await Task.sleep(for: .milliseconds(60))
    #expect(try #require(popover.window).frame == originalFrame)
    popover.close()
    popover.present(relativeTo: anchor.bounds, of: anchor)
    try await Task.sleep(for: .milliseconds(250))
    let newAnchor = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    #expect(abs(try #require(popover.window).frame.midX - newAnchor.midX) < 0.5)
  }

  @Test func screenEdgePlacementMatchesAppKitAndQuitResizesDownward() async throws {
    let screen = try #require(NSScreen.main).frame
    let sourceRect = NSRect(x: screen.midX, y: screen.maxY - 24, width: 24, height: 24)
    let source = NSWindow(
      contentRect: sourceRect, styleMask: [.borderless], backing: .buffered, defer: false)
    source.level = .statusBar
    source.setFrame(sourceRect, display: false)
    source.orderFrontRegardless()
    defer { source.orderOut(nil) }
    let button = try #require(source.contentView)
    button.layoutSubtreeIfNeeded()
    let controller = NSHostingController(rootView: Text("Menu bar fixture"))
    controller.sizingOptions = []
    let native = NSPopover()
    native.animates = false
    native.contentViewController = controller
    native.contentSize = NSSize(width: 200, height: 100)
    native.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    try await Task.sleep(for: .milliseconds(60))
    let nativeFrame = try #require(controller.view.window).frame
    native.close()
    native.contentViewController = nil

    let popover = CleanerPopover()
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 200, height: 100)
    defer { popover.close() }
    popover.present(relativeTo: button.bounds, of: button)
    try await Task.sleep(for: .milliseconds(250))
    let frame = try #require(popover.window).frame
    #expect(frame == nativeFrame)
    popover.resize(to: NSSize(width: 200, height: 64), animated: true)
    try await Task.sleep(for: .milliseconds(250))
    let compact = try #require(popover.window).frame
    #expect(compact.minX == frame.minX)
    #expect(compact.maxY == frame.maxY)
    #expect(compact.height < frame.height)
    popover.resize(to: NSSize(width: 200, height: 100), animated: true)
    try await Task.sleep(for: .milliseconds(250))
    #expect(try #require(popover.window).frame == frame)
  }
}
