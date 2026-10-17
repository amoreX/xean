import AppKit

/// AppKit owns the material, border, pointer and screen-edge placement.
@MainActor
final class CleanerPopover: NSPopover {
  static let contentWidth: CGFloat = 420
  static let contentHeight: CGFloat = 580
  static let quitContentHeight: CGFloat = 64
  static let animationDuration: TimeInterval = 0.18

  var didDismiss: (() -> Void)?
  private(set) var isPresented = false
  private(set) var anchorRect: NSRect = .zero
  private var generation = 0
  var window: NSWindow? { contentViewController?.view.window }

  func updateAnchor(_ rect: NSRect) {
    anchorRect = rect
    // AppKit cannot reposition a popover until its native window has been created.
    if isShown && positioningRect != rect { positioningRect = rect }
  }

  func present(relativeTo rect: NSRect, of view: NSView) {
    anchorRect = rect
    generation += 1
    isPresented = true
    animates = false
    if !isShown {
      appearance = NSApp.effectiveAppearance
      show(relativeTo: rect, of: view, preferredEdge: .minY)
      window?.alphaValue = 0
    }
    window?.makeKey()
    window?.makeFirstResponder(nil)
    animate { [weak self] in self?.window?.animator().alphaValue = 1 }
  }

  func dismissAnimated() {
    guard isPresented else { return }
    isPresented = false
    generation += 1
    let current = generation
    animate(
      { [weak self] in self?.window?.animator().alphaValue = 0 },
      completion: { [weak self] in
        guard let self, self.generation == current, !self.isPresented else { return }
        self.close()
        self.didDismiss?()
      })
  }

  func resize(to size: NSSize, animated: Bool) {
    guard contentSize != size else { return }
    let previousFrame = window?.frame
    contentSize = size
    guard animated, isPresented, let window, let previousFrame else { return }
    let targetFrame = window.frame
    window.setFrame(previousFrame, display: false)
    animate { window.animator().setFrame(targetFrame, display: true) }
  }

  private func animate(_ changes: () -> Void, completion: (@MainActor @Sendable () -> Void)? = nil)
  {
    NSAnimationContext.runAnimationGroup { context in
      context.duration =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ? 0 : Self.animationDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      changes()
    } completionHandler: {
      MainActor.assumeIsolated { completion?() }
    }
  }
}
