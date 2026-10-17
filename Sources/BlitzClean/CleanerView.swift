import SwiftUI

struct CleanerView: View {
  private let colors = BlitzPalette.paper
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var model: CleanerModel
  @ObservedObject var launchAtLogin: LaunchAtLoginController
  @ObservedObject var menuBarStats: CleanerMenuBarStats
  @ObservedObject var presentation = CleanerPopoverPresentation()
  var pointerX: CGFloat?
  var confirmingQuit = false
  var onQuitRequest: () -> Void = {}
  var onQuitCancel: () -> Void = {}
  @State private var confirmAutomatic = false
  @State private var showStatsOptions = false

  var body: some View {
    let visible = presentation.isVisible
    let scale = reduceMotion || visible ? 1.0 : 0.975
    ZStack {
      cleanerContent
        .opacity(confirmingQuit ? 0 : 1)
        .disabled(confirmingQuit)
        .allowsHitTesting(!confirmingQuit)
        .accessibilityHidden(confirmingQuit)
      if confirmingQuit {
        quitConfirmation.transition(.opacity)
      }
    }
    .foregroundStyle(colors.primaryText)
    .padding(.top, CleanerPopoverShape.pointerHeight)
    .background {
      CleanerWindowBackdrop(pointerX: pointerX, cornerRadius: confirmingQuit ? 28 : 22)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: confirmingQuit)
    .environment(\.colorScheme, .light)
    .environment(\.blitzPalette, colors)
    .environment(\.blitzGlassEnabled, true)
    .tint(colors.accent)
    .frame(
      minWidth: 380, idealWidth: 420, maxWidth: .infinity,
      minHeight: confirmingQuit ? 0 : 400,
      idealHeight: confirmingQuit ? CleanerPopoverPlacement.quitContentHeight : 580
    )
    .visualEffect { content, geometry in
      let anchor = UnitPoint(
        x: (pointerX ?? geometry.size.width / 2) / max(1, geometry.size.width), y: 0)
      return
        content
        .scaleEffect(scale, anchor: anchor)
        .opacity(visible ? 1 : 0)
    }
    .accessibilityHidden(!visible)
    .task { await model.refreshDisk() }
  }

  private var cleanerContent: some View {
    VStack(spacing: 0) {
      header.padding(.leading, 18).padding(.trailing, 8).padding(.top, 10).padding(.bottom, 2)

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
          .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.preferences.mode
          )
          .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: model.preferences.warningsEnabled
          )
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: menuBarStats.enabled)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showStatsOptions)
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
      }.font(BlitzType.body).foregroundStyle(colors.secondaryText)
      Button(action: onQuitRequest) {
        Image(systemName: "power").font(.system(size: 14, weight: .medium))
      }.blitzButton(.quiet)
        .accessibilityLabel("Quit xean")
        .help("Quit xean")
    }
  }

  private var quitConfirmation: some View {
    HStack(spacing: 10) {
      Text("Quit xean?").font(.system(size: 15, weight: .semibold)).lineLimit(1)
      Spacer(minLength: 12)
      Button("Cancel", action: onQuitCancel).blitzButton(.secondary).clipShape(Capsule())
      Button("Quit") { AppLifetime.stopMonitoringAndQuit() }.blitzButton(.accent)
        .clipShape(Capsule())
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
        .font(BlitzType.caption).foregroundStyle(colors.secondaryText).cleanerScrollItem()
      }
    }
  }

  private var warningSettings: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle(
        "Notify when low",
        isOn: Binding(
          get: { model.preferences.warningsEnabled },
          set: { enabled in
            model.preferences.warningsEnabled = enabled
            model.sounds.play(.toggle)
          })
      )
      .toggleStyle(BlitzSwitchStyle()).font(BlitzType.body).cleanerScrollItem()
      if model.preferences.warningsEnabled {
        freeSpaceThreshold
      }
    }.disabled(model.isBusy)
  }

  private var freeSpaceThreshold: some View {
    HStack {
      Text("Free space below").font(BlitzType.body)
      Spacer()
      numberField("Free-space limit", value: $model.preferences.freeSpaceGB, range: 1...1_000)
      Text("GB").font(BlitzType.body)
    }.frame(minHeight: 34).padding(.leading, 16).cleanerScrollItem()
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle("Show menu bar stats", isOn: $menuBarStats.enabled)
        .toggleStyle(BlitzSwitchStyle()).font(BlitzType.body).cleanerScrollItem()
        .onChange(of: menuBarStats.enabled) { _, _ in model.sounds.play(.toggle) }
      if menuBarStats.enabled {
        VStack(alignment: .leading, spacing: 0) {
          Button {
            showStatsOptions.toggle()
            model.sounds.play(.toggle)
          } label: {
            HStack {
              Text("Stats shown")
              Spacer()
              Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.secondaryText)
                .rotationEffect(.degrees(showStatsOptions ? 90 : 0))
                .frame(width: 38)
            }.frame(maxWidth: .infinity, minHeight: 34).contentShape(Rectangle())
          }.buttonStyle(.plain).cleanerScrollItem()
            .accessibilityValue(showStatsOptions ? "Expanded" : "Collapsed")
          if showStatsOptions {
            statsOptions
          }
        }.font(BlitzType.body)
          .padding(.leading, 16)
          .onChange(of: menuBarStats.display) { _, _ in model.sounds.play(.toggle) }
      }
      Toggle(
        "Start at login",
        isOn: Binding(get: { launchAtLogin.enabled }, set: { launchAtLogin.setEnabled($0) })
      )
      .toggleStyle(BlitzSwitchStyle()).font(BlitzType.body).cleanerScrollItem()
    }
  }

  private var statsOptions: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle("CPU", isOn: $menuBarStats.display.showCPU)
        .disabled(menuBarStats.display.showCPU && menuBarStats.display.count == 1)
        .cleanerScrollItem()
      Toggle("Memory", isOn: $menuBarStats.display.showMemory)
        .disabled(menuBarStats.display.showMemory && menuBarStats.display.count == 1)
        .cleanerScrollItem()
      if menuBarStats.display.showMemory {
        BlitzSegmentedPicker(
          title: "Memory value", options: MenuBarMemoryDisplay.allCases,
          selection: $menuBarStats.display.memoryDisplay, label: { $0.label }
        ).padding(.vertical, 4).cleanerScrollItem()
      }
      Toggle("Disk free", isOn: $menuBarStats.display.showDisk)
        .disabled(menuBarStats.display.showDisk && menuBarStats.display.count == 1)
        .cleanerScrollItem()
    }.toggleStyle(BlitzSwitchStyle())
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
        automaticConfirmation.transition(.opacity)
      } else {
        automaticToggle.transition(.opacity)
      }
    }
    .font(BlitzType.body).frame(height: 34).cleanerScrollItem()
    .animation(
      reduceMotion ? nil : .smooth(duration: 0.32, extraBounce: 0), value: confirmAutomatic
    )
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
        .toggleStyle(BlitzSwitchStyle(showsLabel: false))
    }
  }

  private var automaticConfirmation: some View {
    HStack(spacing: 6) {
      Text("Auto-clean below").lineLimit(1).fixedSize()
      automaticLimit
      Text("GB?").fixedSize()
      Spacer(minLength: 2)
      Button("Cancel") {
        confirmAutomatic = false
        model.sounds.play(.tap)
      }.blitzButton(.secondary)
      Button("OK") {
        model.preferences.setAutomatic(true)
        model.sounds.play(.select)
        confirmAutomatic = false
      }.blitzButton(.accent).disabled(model.preferences.categories.isEmpty)
        .accessibilityLabel("Enable auto-clean")
    }
  }

  private var automaticLimit: some View {
    numberField(
      "Auto-clean free-space limit", value: $model.preferences.automaticFreeSpaceGB,
      range: 1...1_000, width: 30
    ).help("Automatically clean when free space drops below this many GB.")
  }

  private var footer: some View {
    HStack(spacing: 10) {
      HStack(spacing: 8) {
        if model.isBusy && model.loadingCategory == nil { ProgressView().controlSize(.small) }
        if !model.status.isEmpty {
          Text(model.status).font(BlitzType.caption).foregroundStyle(colors.supportingText)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("cleaner-status")
            .transition(.opacity)
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.status.isEmpty)
      Spacer(minLength: 0)
      Button("Clean") {
        Task { await model.cleanSelected() }
      }.blitzButton(.accent)
        .disabled(model.isBusy || model.preferences.categories.isEmpty)
        .fixedSize()
    }
  }

  private func numberField(
    _ title: String, value: Binding<Int>, range: ClosedRange<Int>, width: CGFloat = 48
  )
    -> some View
  {
    Stepper(
      value: Binding(
        get: { value.wrappedValue },
        set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }), in: range
    ) {
      TextField(title, value: value, format: .number.grouping(.never))
        .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: width)
        .padding(.horizontal, 10).padding(.vertical, 5).blitzGlassSurface(radius: 9)
        .onSubmit {
          value.wrappedValue = min(range.upperBound, max(range.lowerBound, value.wrappedValue))
        }
        .accessibilityLabel(title)
    }.fixedSize()
  }

}
