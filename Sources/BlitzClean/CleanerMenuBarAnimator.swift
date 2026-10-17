import AppKit

/// Reveal stats to the left of the trailing icon without moving the popover's anchor.
@MainActor
final class CleanerMenuBarAnimator {
  private struct Frame: Equatable {
    var width: CGFloat
    var opacity: CGFloat
  }

  private let icon: NSImage
  private let render: (NSImage) -> Void
  private var label: NSImage?
  private var current: Frame
  private var target: Frame?
  private var animation: Task<Void, Never>?

  init(icon: NSImage, render: @escaping (NSImage) -> Void) {
    self.icon = icon
    self.render = render
    current = Frame(width: icon.size.width, opacity: 0)
  }

  func update(image: NSImage?, animated: Bool) {
    if let image { label = image }
    let next = Frame(width: image?.size.width ?? icon.size.width, opacity: image == nil ? 0 : 1)
    guard next != target || !animated else {
      if animation == nil { publish() }
      return
    }
    let firstUpdate = target == nil
    stop()
    target = next
    guard animated, !firstUpdate, next != current else {
      current = next
      publish()
      return
    }
    let start = current
    animation = Task { [weak self] in
      let began = ContinuousClock.now
      while !Task.isCancelled {
        guard let self else { return }
        let progress = min(1, began.duration(to: .now) / .milliseconds(280))
        let eased = CGFloat(progress * progress * (3 - 2 * progress))
        self.current = Frame(
          width: start.width + (next.width - start.width) * eased,
          opacity: start.opacity + (next.opacity - start.opacity) * eased)
        self.publish()
        if progress == 1 {
          self.animation = nil
          return
        }
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
      }
    }
  }

  func stop() {
    animation?.cancel()
    animation = nil
  }

  private func publish() {
    let icon = icon
    let label = label
    let frame = current
    let image = NSImage(
      size: NSSize(width: frame.width, height: icon.size.height), flipped: false
    ) { rect in
      icon.draw(
        at: NSPoint(x: rect.width - icon.size.width, y: 0), from: .zero,
        operation: .sourceOver, fraction: 1)
      if let label, frame.opacity > 0, frame.width > icon.size.width {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
          rect: NSRect(
            x: 0, y: 0, width: rect.width - icon.size.width, height: rect.height)
        ).addClip()
        label.draw(
          at: NSPoint(x: rect.width - label.size.width, y: 0), from: .zero,
          operation: .sourceOver, fraction: frame.opacity)
        NSGraphicsContext.restoreGraphicsState()
      }
      return true
    }
    image.isTemplate = true
    render(image)
  }
}
