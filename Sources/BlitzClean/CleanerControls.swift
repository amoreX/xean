import SwiftUI

extension View {
  @ViewBuilder
  func cleanerButton(prominent: Bool = false) -> some View {
    if #available(macOS 26.0, *) {
      if prominent {
        buttonStyle(.glassProminent)
      } else {
        buttonStyle(.glass)
      }
    } else if prominent {
      buttonStyle(.borderedProminent)
    } else {
      buttonStyle(.bordered)
    }
  }

  func cleanerSwitchRow() -> some View {
    toggleStyle(CleanerSwitchStyle())
  }
}

private struct CleanerSwitchStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Toggle(isOn: configuration.$isOn) {
      configuration.label.frame(maxWidth: .infinity, alignment: .leading)
    }.toggleStyle(.switch).frame(minHeight: 34)
  }
}
