import SwiftUI

struct CleanerView: View {
  @ObservedObject var model: CleanerModel
  @ObservedObject var launchAtLogin: LaunchAtLoginController
  @ObservedObject var menuBarStats: CleanerMenuBarStats
  var confirmingQuit = false
  var onQuitRequest: () -> Void = {}
  var onQuitCancel: () -> Void = {}
  var onClose: () -> Void = {}
  @State private var confirmAutomatic = false
  @State private var presentedRemovals: Set<String> = []

  var body: some View {
    Group {
      if confirmingQuit {
        quitConfirmation
      } else if let cleanup = model.cleanup {
        VStack(spacing: 0) {
          header.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
          CleanerCleanupView(
            model: model, cleanup: cleanup, onClose: onClose,
            presentedRemovals: $presentedRemovals
          )
          .id(cleanup.id)
        }
      } else {
        cleanerContent
      }
    }
    .font(.system(size: 13))
    .foregroundStyle(.primary)
    .frame(width: CleanerPopover.contentWidth)
    .frame(maxHeight: .infinity, alignment: .top)
    .task { await model.refreshDisk() }
    .onChange(of: model.cleanup?.id) { _, _ in presentedRemovals = [] }
  }

  private var cleanerContent: some View {
    VStack(spacing: 0) {
      header.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 4)

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 0) {
            automaticCleanup
            warningSettings
          }
          categories
          settings.padding(.bottom, 8)
        }.padding(.horizontal, 18).padding(.top, 18)
          .background {
            CleanerScrollBehavior().allowsHitTesting(false).accessibilityHidden(true)
          }
      }.cleanerScrollViewport()
      footer.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("xean").font(.system(size: 20, weight: .semibold))
      Spacer(minLength: 8)
      HStack(spacing: 5) {
        if model.lowSpaceWarning {
          Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            .accessibilityLabel("Low disk space")
        }
        Text(model.available.map { ByteText.full($0) + " free" } ?? "Checking space…")
          .monospacedDigit().lineLimit(1)
      }.font(BlitzType.body).foregroundStyle(.secondary)
      Button {
        model.darkTheme.toggle()
        model.sounds.play(.toggle)
      } label: {
        Image(systemName: model.darkTheme ? "sun.max" : "moon")
          .font(.system(size: 14, weight: .medium))
          .frame(width: 22, height: 24)
      }.buttonStyle(.borderless)
        .accessibilityLabel(themeAction)
        .help(themeAction)
      Button(action: onQuitRequest) {
        Image(systemName: "power").font(.system(size: 14, weight: .medium))
      }.buttonStyle(.borderless)
        .accessibilityLabel("Quit xean")
        .help("Quit xean")
    }
  }

  private var themeAction: String {
    model.darkTheme ? "Switch to light theme" : "Switch to dark theme"
  }

  private var quitConfirmation: some View {
    HStack(spacing: 10) {
      Text("Quit xean?").font(.system(size: 15, weight: .semibold)).lineLimit(1)
      Spacer(minLength: 12)
      Button("Cancel", action: onQuitCancel).cleanerButton()
      Button("Quit") { AppLifetime.stopMonitoringAndQuit() }.cleanerButton(prominent: true)
    }.padding(.horizontal, 20).padding(.vertical, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var categories: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("What to clean").font(BlitzType.section).cleanerScrollItem()
      VStack(spacing: 0) {
        ForEach(CleanerCategory.allCases) { category in
          CleanerCategoryRow(model: model, category: category)
        }
      }
      if model.preferences.categories.contains(.worktrees) && model.preferences.mode == .automatic {
        HStack {
          Text("Keep worktrees used in the last").font(BlitzType.body)
          Spacer()
          numberField("Worktree age", value: $model.preferences.worktreeDays, range: 1...365)
          Text("days").font(BlitzType.body)
        }.cleanerScrollItem()
        Text(
          "Age includes file changes and Git activity. Primary, detached, locked, unmerged and dirty worktrees stay."
        )
        .font(BlitzType.caption).foregroundStyle(.secondary).cleanerScrollItem()
      }
    }
  }

  private var warningEnabled: Binding<Bool> {
    Binding(
      get: { model.preferences.warningsEnabled },
      set: { enabled in
        model.preferences.warningsEnabled = enabled
        model.sounds.play(.toggle)
      })
  }

  private var warningSettings: some View {
    HStack(spacing: 8) {
      Text("Notify when low")
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .onTapGesture { warningEnabled.wrappedValue.toggle() }
        .accessibilityHidden(true)
      numberField("Free-space limit", value: $model.preferences.freeSpaceGB, range: 1...1_000)
      Text("GB")
      Toggle("Notify when low", isOn: warningEnabled)
        .labelsHidden().toggleStyle(.switch)
    }.font(BlitzType.body).frame(height: 34).cleanerScrollItem()
      .disabled(model.isBusy)
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Show menu bar stats")
          .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
          .onTapGesture { menuBarStats.enabled.toggle() }
          .accessibilityHidden(true)
        Toggle("Show menu bar stats", isOn: $menuBarStats.enabled)
          .labelsHidden().toggleStyle(.switch)
      }.font(BlitzType.body).frame(height: 34).cleanerScrollItem()
        .onChange(of: menuBarStats.enabled) { _, _ in model.sounds.play(.toggle) }
      CleanerDisclosureReveal(expanded: menuBarStats.enabled) {
        statsOptions.font(BlitzType.body)
          .padding(.leading, 16)
          .onChange(of: menuBarStats.display) { _, _ in model.sounds.play(.toggle) }
      }
      Toggle(
        "Start at login",
        isOn: Binding(get: { launchAtLogin.enabled }, set: { launchAtLogin.setEnabled($0) })
      )
      .cleanerSwitchRow().font(BlitzType.body).cleanerScrollItem()
    }
  }

  private var statsOptions: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle("CPU", isOn: $menuBarStats.display.showCPU).cleanerSwitchRow()
        .disabled(menuBarStats.display.showCPU && menuBarStats.display.count == 1)
        .cleanerScrollItem()
      Toggle("Memory", isOn: $menuBarStats.display.showMemory).cleanerSwitchRow()
        .disabled(menuBarStats.display.showMemory && menuBarStats.display.count == 1)
        .cleanerScrollItem()
      if menuBarStats.display.showMemory {
        Picker("Memory value", selection: $menuBarStats.display.memoryDisplay) {
          ForEach(MenuBarMemoryDisplay.allCases, id: \.self) { value in
            Text(value.label).tag(value)
          }
        }.pickerStyle(.segmented).labelsHidden().padding(.vertical, 6).cleanerScrollItem()
      }
      Toggle("Disk free", isOn: $menuBarStats.display.showDisk).cleanerSwitchRow()
        .disabled(menuBarStats.display.showDisk && menuBarStats.display.count == 1)
        .cleanerScrollItem()
    }.toggleStyle(.switch)
  }

  private var automaticEnabled: Binding<Bool> {
    Binding(
      get: { model.preferences.mode == .automatic },
      set: { enabled in
        if enabled {
          confirmAutomatic = true
          model.sounds.play(.warning)
        } else {
          confirmAutomatic = false
          model.preferences.setAutomatic(false)
          model.sounds.play(.toggle)
        }
      })
  }

  private var automaticCleanup: some View {
    ZStack {
      if confirmAutomatic {
        automaticConfirmation
      } else {
        automaticToggle
      }
    }
    .font(BlitzType.body).frame(height: 34).cleanerScrollItem()
    .disabled(model.isBusy)
  }

  private var automaticToggle: some View {
    HStack(spacing: 8) {
      Text("Auto-clean")
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .onTapGesture { automaticEnabled.wrappedValue.toggle() }
        .accessibilityHidden(true)
      automaticLimit
      Text("GB")
      Toggle("Auto-clean", isOn: automaticEnabled)
        .labelsHidden().toggleStyle(.switch)
    }
  }

  private var automaticConfirmation: some View {
    HStack(spacing: 6) {
      Text("Enable auto-clean?").lineLimit(1)
      Spacer(minLength: 2)
      Button("Cancel") {
        confirmAutomatic = false
        model.sounds.play(.tap)
      }.cleanerButton()
      Button("OK") {
        model.preferences.setAutomatic(true)
        model.sounds.play(.select)
        confirmAutomatic = false
      }.cleanerButton(prominent: true).disabled(model.preferences.categories.isEmpty)
        .accessibilityLabel("Enable auto-clean")
    }
  }

  private var automaticLimit: some View {
    numberField(
      "Auto-clean free-space limit", value: $model.preferences.automaticFreeSpaceGB,
      range: 1...1_000, width: 48
    ).help("Automatically clean when free space drops below this many GB.")
  }

  private var footer: some View {
    HStack(spacing: 10) {
      HStack(spacing: 8) {
        if model.isBusy && model.loadingCategory == nil { ProgressView().controlSize(.small) }
        if !model.status.isEmpty {
          Text(model.status).font(BlitzType.caption).foregroundStyle(.secondary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("cleaner-status")
        }
      }
      Spacer(minLength: 0)
      Button("Clean") {
        Task { await model.cleanSelected() }
      }.cleanerButton(prominent: true)
        .disabled(model.isBusy || model.preferences.categories.isEmpty)
        .fixedSize()
    }
  }

  private func numberField(
    _ title: String, value: Binding<Int>, range: ClosedRange<Int>, width: CGFloat = 48
  )
    -> some View
  {
    TextField(title, value: value, format: .number.grouping(.never))
      .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: width)
      .onSubmit {
        value.wrappedValue = min(range.upperBound, max(range.lowerBound, value.wrappedValue))
      }
      .accessibilityLabel(title)
  }

}
