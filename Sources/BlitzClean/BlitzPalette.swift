import SwiftUI

/// Shared controls keep their existing dark appearance unless a surface selects the paper palette.
struct BlitzPalette {
  let canvas: Color
  let panel: Color
  let primaryText: Color
  let supportingText: Color
  let secondaryText: Color
  let separator: Color
  let panelStroke: Color
  let strongStroke: Color
  let controlFill: Color
  let hoverFill: Color
  let selectedFill: Color
  let quietFill: Color
  let strongFill: Color
  let accent: Color
  let onAccent: Color

  static let dark = BlitzPalette(
    canvas: BlitzUI.canvasBackground, panel: BlitzUI.panelBackground,
    primaryText: BlitzUI.primaryText, supportingText: BlitzUI.supportingText,
    secondaryText: BlitzUI.secondaryText, separator: BlitzUI.separator,
    panelStroke: BlitzUI.panelStroke, strongStroke: BlitzUI.strongStroke,
    controlFill: BlitzUI.controlFill, hoverFill: BlitzUI.hoverFill,
    selectedFill: BlitzUI.selectedFill, quietFill: BlitzUI.quietFill,
    strongFill: BlitzUI.strongFill, accent: BlitzUI.mint, onAccent: .black.opacity(0.88))

  static let paper = BlitzPalette(
    canvas: Color(red: 0.975, green: 0.973, blue: 0.966), panel: .white,
    primaryText: Color(white: 0.14), supportingText: Color(white: 0.32),
    secondaryText: Color(white: 0.42), separator: .black.opacity(0.08),
    panelStroke: .black.opacity(0.12), strongStroke: .black.opacity(0.28),
    controlFill: .black.opacity(0.045), hoverFill: .black.opacity(0.075),
    selectedFill: .white, quietFill: .black.opacity(0.035),
    strongFill: .black.opacity(0.22), accent: Color(white: 0.18), onAccent: .white)
}

private struct BlitzPaletteKey: EnvironmentKey {
  static let defaultValue = BlitzPalette.dark
}

extension EnvironmentValues {
  var blitzPalette: BlitzPalette {
    get { self[BlitzPaletteKey.self] }
    set { self[BlitzPaletteKey.self] = newValue }
  }
}
