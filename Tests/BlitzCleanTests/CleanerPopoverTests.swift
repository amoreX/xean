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
    popover.updateAnchor(anchor.bounds)
    #expect(popover.anchorRect == anchor.bounds)
    #expect(!popover.isShown)
    popover.present(relativeTo: popover.anchorRect, of: anchor)
    popover.updateAnchor(anchor.bounds.insetBy(dx: 1, dy: 0))
    #expect(popover.positioningRect == anchor.bounds.insetBy(dx: 1, dy: 0))
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
}
