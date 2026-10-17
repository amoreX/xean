import AppKit
import Testing

@testable import BlitzClean

struct CleanerPopoverTests {
  @Test func quitConfirmationKeepsTheSameTopEdgeAndIconAnchor() {
    let screen = NSRect(x: 0, y: 0, width: 1_440, height: 876)
    for x in [16.0, 700.0, 1_400.0] {
      let anchor = NSRect(x: x, y: 876, width: 24, height: 24)
      let cleaner = CleanerPopoverPlacement(anchor: anchor, visibleFrame: screen)
      let confirmation = CleanerPopoverPlacement(
        anchor: anchor, visibleFrame: screen,
        contentHeight: CleanerPopoverPlacement.quitContentHeight)
      #expect(confirmation.frame.maxY == cleaner.frame.maxY)
      #expect(confirmation.frame.minX == cleaner.frame.minX)
      #expect(confirmation.frame.width == cleaner.frame.width)
      #expect(confirmation.frame.height == 72)
      #expect(confirmation.pointerX == cleaner.pointerX)
      #expect(screen.contains(confirmation.frame))
    }
  }

  @Test func centeredPointerMeetsMenuBarIcon() {
    let anchor = NSRect(x: 1_190, y: 976, width: 24, height: 24)
    let screen = NSRect(x: 0, y: 0, width: 1_920, height: 976)
    let placement = CleanerPopoverPlacement(anchor: anchor, visibleFrame: screen)
    #expect(placement.frame.midX == anchor.midX)
    #expect(placement.pointerX == placement.frame.width / 2)
    #expect(placement.frame.maxY == anchor.minY - 3)
  }

  @Test func screenEdgesKeepThePanelVisibleAndPointerOnTheIcon() {
    let screen = NSRect(x: 0, y: 0, width: 1_440, height: 876)
    for x in [16.0, 1_400.0] {
      let anchor = NSRect(x: x, y: 876, width: 24, height: 24)
      let placement = CleanerPopoverPlacement(anchor: anchor, visibleFrame: screen)
      #expect(screen.contains(placement.frame))
      #expect(placement.frame.minX + placement.pointerX == anchor.midX)
    }
  }

  @Test func secondaryDisplayUsesItsOwnCoordinateSpace() {
    let screen = NSRect(x: -1_920, y: 100, width: 1_920, height: 1_056)
    let anchor = NSRect(x: -600, y: 1_156, width: 24, height: 24)
    let placement = CleanerPopoverPlacement(anchor: anchor, visibleFrame: screen)
    #expect(screen.contains(placement.frame))
    #expect(placement.frame.midX == anchor.midX)
    #expect(placement.frame.minX + placement.pointerX == anchor.midX)
  }

  @Test func shortDisplayKeepsTheFooterAboveItsLowerEdge() {
    let screen = NSRect(x: 0, y: 48, width: 1_024, height: 552)
    let anchor = NSRect(x: 700, y: 600, width: 24, height: 24)
    let placement = CleanerPopoverPlacement(anchor: anchor, visibleFrame: screen)
    #expect(screen.contains(placement.frame))
    #expect(placement.frame.minY == screen.minY + 8)
    #expect(placement.frame.maxY == anchor.minY - 3)
  }
}
