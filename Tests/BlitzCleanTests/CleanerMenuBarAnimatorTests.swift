import AppKit
import Testing

@testable import BlitzClean

@MainActor
struct CleanerMenuBarAnimatorTests {
  @Test func rapidToggleReversesFromTheCurrentWidthAndFinishesAtTheLatestChoice() async throws {
    var widths: [CGFloat] = []
    let animator = CleanerMenuBarAnimator(icon: NSImage(size: .init(width: 20, height: 22))) {
      widths.append($0.size.width)
    }
    defer { animator.stop() }
    let expanded = NSImage(size: .init(width: 220, height: 22))
    animator.update(image: expanded, animated: false)
    #expect(widths.last == 220)
    animator.update(image: nil, animated: true)
    for _ in 0..<100 {
      if let width = widths.last, width < 220 { break }
      try await Task.sleep(for: .milliseconds(2))
    }
    let halfway = try #require(widths.last)
    #expect(halfway > 20 && halfway < 220)
    animator.update(image: expanded, animated: true)
    #expect(widths.last == halfway)
    try await Task.sleep(for: .milliseconds(400))
    #expect(widths.last == 220)

    animator.update(image: nil, animated: true)
    try await Task.sleep(for: .milliseconds(100))
    animator.update(image: nil, animated: true)
    try await Task.sleep(for: .milliseconds(300))
    #expect(widths.last == 20)
  }

  @Test func reducedMotionFinishesImmediatelyAndCancelsAnInFlightTransition() async throws {
    var width: CGFloat = 0
    let animator = CleanerMenuBarAnimator(icon: NSImage(size: .init(width: 20, height: 22))) {
      width = $0.size.width
    }
    defer { animator.stop() }
    let expanded = NSImage(size: .init(width: 220, height: 22))
    animator.update(image: nil, animated: false)
    animator.update(image: expanded, animated: true)
    try await Task.sleep(for: .milliseconds(30))
    animator.update(image: expanded, animated: false)
    #expect(width == 220)
    animator.update(image: nil, animated: false)
    #expect(width == 20)
    try await Task.sleep(for: .milliseconds(350))
    #expect(width == 20)
  }
}
