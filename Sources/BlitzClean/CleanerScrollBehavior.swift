import AppKit
import QuartzCore
import SwiftUI

/// Smooth discrete mouse wheels; precise trackpad gestures keep AppKit's momentum.
struct CleanerScrollBehavior: NSViewRepresentable {
  func makeNSView(context: Context) -> WheelSmoother { WheelSmoother() }
  func updateNSView(_ view: WheelSmoother, context: Context) {}

  static func dismantleNSView(_ view: WheelSmoother, coordinator: ()) {
    view.stopMonitoring()
  }

  final class WheelSmoother: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        guard let self else { return event }
        return self.smooth(event)
      }
    }

    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }

    private func smooth(_ event: NSEvent) -> NSEvent? {
      guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaY != 0,
        event.scrollingDeltaX == 0, event.window === window,
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        let scroll = enclosingScrollView,
        scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil))
      else { return event }
      let clip = scroll.contentView
      var bounds = clip.bounds
      bounds.origin.y += event.scrollingDeltaY * 18 * (clip.isFlipped ? -1 : 1)
      let destination = clip.constrainBoundsRect(bounds)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        clip.animator().bounds = destination
      }
      return nil
    }
  }
}
