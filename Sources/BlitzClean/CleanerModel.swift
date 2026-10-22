import AppKit
import Foundation

struct CleanerOutcome: Codable, Sendable {
  let date: Date
  let removed: Int
  let kept: Int
  let bytes: UInt64
  let availableGain: UInt64?

  var summary: String {
    "Removed \(removed) \(removed == 1 ? "item" : "items") · \(ByteText.full(bytes))"
      + (kept > 0 ? " · \(kept) kept" : "")
  }
}

struct CleanerCleanup: Identifiable {
  enum Phase { case scanning, removing, finished }
  let id = UUID()
  var phase: Phase = .scanning
  var items: [CleanerItem] = []
  var removedIDs: Set<String> = []
  var result: CleanerOutcome?
  var protectedCount = 0
  var notes: [String] = []
}

@MainActor
final class CleanerModel: ObservableObject {
  @Published var darkTheme: Bool {
    didSet { defaults.set(darkTheme, forKey: "cleaner.darkTheme") }
  }
  @Published var preferences: CleanerPreferences {
    didSet {
      if preferences != preferences.normalized { preferences = preferences.normalized }
      preferences.save(defaults)
      if !sameScope(preferences, oldValue) {
        scan = nil
      }
      if preferences.projectRoots != oldValue.projectRoots
        || preferences.worktreeDays != oldValue.worktreeDays
      {
        categoryScans = [:]
        itemFailures = [:]
      }
      if preferences.mode != oldValue.mode {
        nextCheck = .now.addingTimeInterval(Double(preferences.normalized.checkMinutes) * 60)
      }
    }
  }
  @Published private(set) var scan: CleanerScan?
  @Published private(set) var categoryScans: [CleanerCategory: CleanerScan] = [:]
  @Published private(set) var loadingCategory: CleanerCategory?
  @Published private(set) var removingItemIDs: Set<String> = []
  @Published private(set) var removingItemID: String?
  @Published private(set) var removedItemIDs: Set<String> = []
  @Published private(set) var itemFailures: [String: String] = [:]
  @Published private(set) var isBusy = false
  @Published private(set) var stopRequested = false
  @Published private(set) var status = "" {
    didSet {
      statusDismissal?.cancel()
      statusDismissal = nil
    }
  }
  @Published private(set) var available: UInt64?
  @Published private(set) var outcome: CleanerOutcome?
  @Published private(set) var cleanup: CleanerCleanup?
  @Published private(set) var nextCheck: Date?
  let sounds: CleanerSounds
  private let defaults: UserDefaults
  private let driver: any CleanerDriver
  private let history: CleanupHistoryStore
  private let now: () -> Date
  private var timer: Task<Void, Never>?
  private var statusDismissal: Task<Void, Never>?

  init(
    defaults: UserDefaults = .standard, driver: any CleanerDriver = NativeCleanerDriver(),
    history: CleanupHistoryStore = .application, now: @escaping () -> Date = { .now }
  ) {
    self.defaults = defaults
    sounds = CleanerSounds()
    self.driver = driver
    self.history = history
    self.now = now
    darkTheme = defaults.bool(forKey: "cleaner.darkTheme")
    preferences = CleanerPreferences.load(defaults)
    if let data = defaults.data(forKey: "cleaner.lastOutcome") {
      outcome = try? JSONDecoder().decode(CleanerOutcome.self, from: data)
    }
  }

  var lowSpaceWarning: Bool {
    preferences.warningsEnabled && preferences.isBelowThreshold(available)
  }

  func start() {
    guard timer == nil else { return }
    let last = defaults.object(forKey: "cleaner.lastCheck") as? Date ?? .distantPast
    nextCheck = max(
      .now.addingTimeInterval(60),
      last.addingTimeInterval(Double(preferences.normalized.checkMinutes) * 60))
    timer = Task { [weak self] in
      await self?.refreshDisk()
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(60)) } catch { break }
        await self?.backgroundCheck()
      }
    }
  }

  func stop() {
    stopRequested = true
    timer?.cancel()
    timer = nil
  }

  func requestStop() {
    stopRequested = true
    status = "Stopping after the current check or removal finishes…"
  }

  func refreshDisk() async { available = await driver.availableBytes() }

  func prepareCategory(_ category: CleanerCategory) {
    guard let report = categoryScans[category] else { return }
    let age = now().timeIntervalSince(report.scannedAt)
    if age < 0 || age > 30 { invalidateCategories([category]) }
  }

  private func invalidateCategories(_ categories: Set<CleanerCategory>) {
    for category in categories {
      if let previous = categoryScans.removeValue(forKey: category) {
        for item in previous.items { itemFailures[item.id] = nil }
      }
    }
  }

  private func cache(_ report: CleanerScan, categories: Set<CleanerCategory>) {
    let completedAt = now()
    for category in categories {
      categoryScans[category] = CleanerScan(
        items: report.items.filter { $0.category == category },
        kept: report.kept.filter { $0.category == category },
        notes: report.categoryNotes[category] ?? report.notes,
        scannedAt: completedAt)
    }
  }

  func loadCategory(_ category: CleanerCategory) async {
    guard !isBusy else { return }
    prepareCategory(category)
    guard categoryScans[category] == nil else { return }
    isBusy = true
    stopRequested = false
    loadingCategory = category
    let original = preferences.normalized
    var requested = original
    requested.categories = [category]
    let report = await driver.scan(requested, automatic: false)
    if !stopRequested, sameScope(original, preferences) {
      cache(report, categories: [category])
    } else {
      status = "Check stopped. Nothing was deleted."
    }
    loadingCategory = nil
    isBusy = false
  }

  func deleteItem(_ requestedItem: CleanerItem) async {
    guard !isBusy,
      let item = categoryScans[requestedItem.category]?.items.first(where: {
        $0.id == requestedItem.id
      })
    else { return }
    isBusy = true
    stopRequested = false
    sounds.play(.tap)
    await clean(
      [item], requested: preferences.normalized, automatic: false, singleCategory: item.category)
    isBusy = false
  }

  func refreshScans() async {
    guard !isBusy, cleanup == nil else { return }
    isBusy = true
    stopRequested = false
    defer { isBusy = false }
    let original = preferences.normalized
    var requested = original
    requested.categories.formUnion(categoryScans.keys)
    invalidateCategories(Set(categoryScans.keys))
    scan = nil
    status = "Refreshing scans…"
    let projectCategories = requested.categories.intersection([.builds, .dependencies, .worktrees])
    let groups = [requested.categories.subtracting(projectCategories), projectCategories]
    for categories in groups where !categories.isEmpty {
      guard !stopRequested, sameScope(original, preferences) else { break }
      status =
        categories == projectCategories
        ? "Checking project folders and worktrees…" : "Refreshing caches…"
      var batch = requested
      batch.categories = categories
      let report = await driver.scan(batch, automatic: false)
      if !stopRequested, sameScope(original, preferences) {
        cache(report, categories: categories)
      }
    }
    if stopRequested {
      status = "Refresh stopped. Nothing was deleted."
    } else if sameScope(original, preferences) {
      status = "Scans refreshed."
    } else {
      status = "Selections changed. Refresh again."
    }
    await refreshDisk()
  }

  func scanNow() async {
    guard !isBusy, !preferences.categories.isEmpty else { return }
    isBusy = true
    stopRequested = false
    await scanSelection(preferences.normalized)
    isBusy = false
  }

  private func scanSelection(_ requested: CleanerPreferences) async {
    scan = nil
    status = "Scanning selected caches and project folders…"
    for category in requested.categories { prepareCategory(category) }
    var missing = requested
    missing.categories = requested.categories.filter { categoryScans[$0] == nil }
    if !missing.categories.isEmpty {
      let report = await driver.scan(missing, automatic: false)
      if !stopRequested, sameScope(requested, preferences) {
        cache(report, categories: missing.categories)
      }
    }
    if stopRequested {
      status = "Scan stopped. Nothing was deleted."
    } else if sameScope(requested, preferences) {
      let reports = CleanerCategory.allCases.filter(requested.categories.contains)
        .compactMap { categoryScans[$0] }
      var report = CleanerScan(
        items: reports.flatMap(\.items), kept: reports.flatMap(\.kept),
        notes: reports.flatMap(\.notes), scannedAt: now())
      CleanerScanner.consolidate(&report)
      scan = report
      status =
        report.items.isEmpty
        ? "No eligible items found."
        : "Found \(report.items.count) eligible items."
    } else {
      status = "Selections changed. Choose Clean to rescan."
    }
    await refreshDisk()
  }

  /// Closing the panel clears this presentation, never an in-flight cleanup.
  func panelClosed() {
    cleanup = nil
    removedItemIDs = []
    if !isBusy { status = "" }
  }

  func cleanSelected() async {
    guard !isBusy, !preferences.categories.isEmpty else { return }
    sounds.play(.tap)
    isBusy = true
    stopRequested = false
    let run = CleanerCleanup()
    cleanup = run
    defer { isBusy = false }
    let requested = preferences.normalized
    await scanSelection(requested)
    guard !stopRequested, requested == preferences.normalized, let report = scan else {
      if cleanup?.id == run.id { cleanup = nil }
      return
    }
    if cleanup?.id == run.id {
      cleanup?.items = report.items
      cleanup?.protectedCount = report.kept.count
      cleanup?.notes = Array(Set(report.notes)).sorted()
      cleanup?.phase = .removing
    }
    let result: CleanerOutcome
    if report.items.isEmpty {
      result = CleanerOutcome(date: now(), removed: 0, kept: 0, bytes: 0, availableGain: 0)
    } else {
      result = await clean(report.items, requested: requested, automatic: false, runID: run.id)
    }
    if cleanup?.id == run.id {
      cleanup?.result = result
      cleanup?.phase = .finished
    }
  }

  func backgroundCheck(now: Date = .now) async {
    guard !isBusy, preferences.mode != .manual,
      nextCheck.map({ now >= $0 }) ?? true
    else { return }
    isBusy = true
    stopRequested = false
    let requested = preferences.normalized
    nextCheck = now.addingTimeInterval(Double(requested.checkMinutes) * 60)
    defaults.set(now, forKey: "cleaner.lastCheck")
    await refreshDisk()
    guard !stopRequested, requested == preferences.normalized,
      requested.isBelowThreshold(available, automatic: requested.mode == .automatic)
    else {
      isBusy = false
      return
    }
    if requested.mode == .automatic, !requested.categories.isEmpty {
      scan = nil
      invalidateCategories(requested.categories)
      status = "Disk space is below your limit. Checking selected categories…"
      let report = await driver.scan(requested, automatic: true)
      guard !stopRequested, requested == preferences.normalized else {
        status = "Automatic cleanup stopped. Nothing was deleted."
        isBusy = false
        return
      }
      scan = report
      // A long scan may finish after another app has already freed enough space.
      await refreshDisk()
      if requested.isBelowThreshold(available, automatic: true) {
        if report.items.isEmpty {
          status = "Disk space is low; no eligible items could be cleaned."
        } else {
          await clean(report.items, requested: requested, automatic: true)
        }
      } else {
        status = "Free space recovered during the scan. No cleanup needed."
      }
    }
    isBusy = false
  }

  @discardableResult
  private func clean(
    _ items: [CleanerItem], requested: CleanerPreferences, automatic: Bool,
    singleCategory: CleanerCategory? = nil, runID: UUID? = nil
  ) async -> CleanerOutcome {
    var deletionPreferences = requested
    if let singleCategory { deletionPreferences.categories.insert(singleCategory) }
    let before = await driver.availableBytes()
    var removed: Set<String> = []
    var failures: [String] = []
    var bytes: UInt64 = 0
    defer {
      removingItemID = nil
      removingItemIDs = []
    }
    await withTaskGroup(of: CleanerDeletionResult.self) { group in
      var pending = items[...]
      var active: [CleanerItem] = []
      var completed = 0
      var reportedStop = false
      while !pending.isEmpty || !active.isEmpty {
        let stopped = stopRequested || requested != preferences.normalized
        if stopped, !pending.isEmpty {
          pending = []
          if !reportedStop {
            failures.append("Remaining cleanup stopped; untouched items were kept.")
            reportedStop = true
          }
        }
        while !pending.isEmpty, active.count < 3,
          let item = pending.first, CleanerDeletionResult.canStart(item, alongside: active)
        {
          pending.removeFirst()
          active.append(item)
          itemFailures[item.id] = nil
          let driver = driver
          let preferences = deletionPreferences
          group.addTask {
            do {
              let win = try await driver.remove(
                item, preferences: preferences, automatic: automatic)
              return CleanerDeletionResult(item: item, win: win, failure: nil)
            } catch {
              return CleanerDeletionResult(
                item: item, win: nil, failure: error.localizedDescription)
            }
          }
        }
        removingItemIDs = Set(active.map(\.id))
        removingItemID = active.first?.id
        guard let finished = await group.next() else { break }
        let item = finished.item
        active.removeAll { $0.id == item.id }
        completed += 1
        status = "Cleaning · \(completed) of \(items.count) finished…"
        if let win = finished.win {
          removed.insert(item.id)
          if !automatic { removedItemIDs.insert(item.id) }
          if let runID, cleanup?.id == runID { cleanup?.removedIDs.insert(item.id) }
          bytes += win.bytes ?? 0
          func wasRemoved(_ path: String) -> Bool {
            path == item.path || path.hasPrefix(item.path + "/")
          }
          scan?.items.removeAll { wasRemoved($0.path) }
          scan?.kept.removeAll { wasRemoved($0.path) }
          for category in Array(categoryScans.keys) {
            categoryScans[category]?.items.removeAll { wasRemoved($0.path) }
            categoryScans[category]?.kept.removeAll { wasRemoved($0.path) }
          }
          let history = history
          do {
            try await Task.detached(priority: .utility) {
              _ = try history.merge(CleanupLedger(wins: [win]))
            }.value
          } catch {
            failures.append(
              "Cleanup succeeded, but its history could not be saved: \(error.localizedDescription)"
            )
          }
        } else if let failure = finished.failure {
          itemFailures[item.id] = failure
          failures.append("\(item.path): \(failure)")
        }
      }
    }
    await refreshDisk()
    let gain = before.flatMap { old in available.map { $0 > old ? $0 - old : 0 } }
    let result = CleanerOutcome(
      date: .now, removed: removed.count, kept: items.count - removed.count,
      bytes: bytes, availableGain: gain)
    outcome = result
    if let data = try? JSONEncoder().encode(result) {
      defaults.set(data, forKey: "cleaner.lastOutcome")
    }
    scan?.notes = Array((failures + (scan?.notes ?? [])).prefix(150))
    status = result.summary
    statusDismissal = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      guard !Task.isCancelled else { return }
      self?.status = ""
    }
    if !automatic {
      sounds.play(.cleanup(removed: result.removed, kept: max(result.kept, failures.count)))
    }
    return result
  }

  private func sameScope(_ a: CleanerPreferences, _ b: CleanerPreferences) -> Bool {
    a.categories == b.categories && a.worktreeDays == b.worktreeDays
      && a.projectRoots == b.projectRoots
  }
}
