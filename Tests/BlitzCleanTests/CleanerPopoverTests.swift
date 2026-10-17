import AppKit
import SwiftUI
import Testing

@testable import BlitzClean

@MainActor
struct CleanerPopoverTests {
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
}
