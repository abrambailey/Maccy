import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

@Observable
class History { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var items: [HistoryItemDecorator] = []
  var selectedItem: HistoryItemDecorator? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
  }

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        // Load all items when searching (so we can search everything)
        if !searchQuery.isEmpty && !isFullyLoaded {
          Task {
            try? await loadAllItems()
            updateItems(search.search(string: searchQuery, within: all))
            AppState.shared.highlightFirst()
            AppState.shared.popup.needsResize = true
          }
        } else {
          updateItems(search.search(string: searchQuery, within: all))

          if searchQuery.isEmpty {
            // When clearing search, reset to showing only initial items
            Task { @MainActor in
              if isFullyLoaded {
                try? await reload()
              }
            }
            AppState.shared.selection = unpinnedItems.first?.id
          } else {
            AppState.shared.highlightFirst()
          }

          AppState.shared.popup.needsResize = true
        }
      }
    }
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return items.first { $0.shortcuts.contains(where: { $0.key == key }) }
  }

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.8)

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  @ObservationIgnored
  var isFullyLoaded = false

  @ObservationIgnored
  private var lastLoadedCount = 0

  @ObservationIgnored
  private var isCurrentlyLoading = false

  init() {
    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await _ in Defaults.updates(.sortBy, initial: false) {
        try? await reload()
      }
    }

    Task {
      for await _ in Defaults.updates(.pinTo, initial: false) {
        try? await reload()
      }
    }

    Task {
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        items.forEach { item in
          let title = item.item.generateTitle()
          item.title = title
          item.item.title = title
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in items {
          await item.sizeImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    // Prevent concurrent loads
    guard !isCurrentlyLoading else {
      print("MACCYDEBUG: load() - already loading, returning")
      return
    }

    // If we already have items, don't reload
    guard all.isEmpty else {
      print("MACCYDEBUG: load() - already have \(all.count) items, returning")
      items = all
      return
    }

    isCurrentlyLoading = true
    defer { isCurrentlyLoading = false }

    // Check total count in DB
    let countDescriptor = FetchDescriptor<HistoryItem>()
    let totalCount = try Storage.shared.context.fetchCount(countDescriptor)

    // Load only first 7 items for instant display
    var descriptor = FetchDescriptor<HistoryItem>(
      sortBy: [SortDescriptor(\HistoryItem.lastCopiedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 7
    let initialResults = try Storage.shared.context.fetch(descriptor)

    // Apply full sorting (including pin logic)
    all = sorter.sort(initialResults).map { HistoryItemDecorator($0) }
    items = all

    print("MACCYDEBUG: load() - loaded \(all.count) items, totalCount=\(totalCount)")

    updateShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }

    // Mark as fully loaded if we got everything
    if totalCount <= 7 {
      isFullyLoaded = true
    }
    lastLoadedCount = all.count
  }

  @MainActor
  func loadMoreItems() async throws {
    print("MACCYDEBUG: loadMoreItems() called, currentCount=\(all.count), isFullyLoaded=\(isFullyLoaded)")

    // If already fully loaded, nothing to do
    guard !isFullyLoaded else {
      print("MACCYDEBUG: loadMoreItems() - already fully loaded, returning")
      return
    }

    // Get total count
    let countDescriptor = FetchDescriptor<HistoryItem>()
    let totalCount = try Storage.shared.context.fetchCount(countDescriptor)

    // Load next 7 items
    var descriptor = FetchDescriptor<HistoryItem>(
      sortBy: [SortDescriptor(\HistoryItem.lastCopiedAt, order: .reverse)]
    )
    descriptor.fetchOffset = all.count
    descriptor.fetchLimit = 7
    let nextResults = try Storage.shared.context.fetch(descriptor)

    print("MACCYDEBUG: loadMoreItems() - fetched \(nextResults.count) more items (offset=\(all.count))")

    // Append new items
    let newItems = sorter.sort(nextResults).map { HistoryItemDecorator($0) }
    all.append(contentsOf: newItems)

    // Only update visible items if no search is active
    if searchQuery.isEmpty {
      items = all
    }

    updateShortcuts()

    // Check if we've loaded everything
    if all.count >= totalCount {
      isFullyLoaded = true
      print("MACCYDEBUG: loadMoreItems() - now fully loaded (\(all.count) items)")
    }

    lastLoadedCount = all.count
  }

  @MainActor
  func loadAllItems() async throws {
    print("MACCYDEBUG: loadAllItems() called, isFullyLoaded=\(isFullyLoaded)")

    // If already fully loaded, nothing to do
    guard !isFullyLoaded else {
      print("MACCYDEBUG: loadAllItems() - already fully loaded, returning")
      return
    }

    // Fetch all items from DB
    let descriptor = FetchDescriptor<HistoryItem>()
    let allResults = try Storage.shared.context.fetch(descriptor)
    let sorted = sorter.sort(allResults)

    // Replace with all items
    all = sorted.map { HistoryItemDecorator($0) }

    print("MACCYDEBUG: loadAllItems() - loaded \(all.count) total items")

    // Only update visible items if no search is active
    if searchQuery.isEmpty {
      items = all
    }

    updateShortcuts()

    isFullyLoaded = true
    lastLoadedCount = all.count
  }

  @MainActor
  func reload() async throws {
    isFullyLoaded = false
    lastLoadedCount = 0
    all.removeAll()
    try await load()
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    while all.filter(\.isUnpinned).count >= Defaults[.size] {
      delete(all.last(where: \.isUnpinned))
    }

    var removedItemIndex: Int?
    var isNewItem = false
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      Storage.shared.context.delete(existingHistoryItem)
      removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
      if let removedItemIndex {
        all.remove(at: removedItemIndex)
      }
    } else {
      isNewItem = true
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    sessionLog[Clipboard.shared.changeCount] = item

    var itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      // Keep pins in the same place.
      if let removedItemIndex {
        all.insert(itemDecorator, at: removedItemIndex)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)

      // Just insert at beginning of unpinned items - no need to sort
      // When user opens Maccy, load() will fetch properly sorted from DB
      let firstUnpinnedIndex = all.firstIndex(where: { $0.isUnpinned }) ?? all.endIndex
      all.insert(itemDecorator, at: firstUnpinnedIndex)

      // Only update items if no search is active
      if searchQuery.isEmpty {
        items = all
      }
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    }

    // Update the loaded count to reflect DB state
    // The DB count increased by 1 (or stayed same if duplicate)
    if isNewItem {
      // New item added to DB
      lastLoadedCount += 1
    }
    // If duplicate, count stayed the same (deleted old, added new = net zero)

    return itemDecorator
  }

  @MainActor
  private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
    func dataCounts() -> String {
      let historyItemCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
      let historyContentCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>())
      return "HistoryItem=\(historyItemCount ?? 0) HistoryItemContent=\(historyContentCount ?? 0)"
    }

    logger.info("\(msg) Before: \(dataCounts())")
    try? block()
    logger.info("\(msg) After: \(dataCounts())")
  }

  @MainActor
  func clear() {
    withLogging("Clearing history") {
      all.forEach { item in
        if item.isUnpinned {
          cleanup(item)
        }
      }
      all.removeAll(where: \.isUnpinned)
      sessionLog.removeValues { $0.pin == nil }
      items = all

      try? Storage.shared.context.delete(
        model: HistoryItem.self,
        where: #Predicate { $0.pin == nil }
      )
      try? Storage.shared.context.delete(
        model: HistoryItemContent.self,
        where: #Predicate { $0.item?.pin == nil }
      )
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearAll() {
    withLogging("Clearing all history") {
      all.forEach { item in
        cleanup(item)
      }
      all.removeAll()
      sessionLog.removeAll()
      items = all

      try? Storage.shared.context.delete(model: HistoryItem.self)
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    cleanup(item)
    withLogging("Removing history item") {
      Storage.shared.context.delete(item.item)
      try? Storage.shared.context.save()
    }

    all.removeAll { $0 == item }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  private func cleanup(_ item: HistoryItemDecorator) {
    item.imageGenerationTask?.cancel()
    item.thumbnailImage?.recache()
    item.previewImage?.recache()
    item.thumbnailImage = nil
    item.previewImage = nil
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else {
      return
    }

    let modifierFlags = NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.togglePin()

    let sortedItems = sorter.sort(all.map(\.item))
    if let currentIndex = all.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      all.remove(at: currentIndex)
      all.insert(item, at: newIndex)
    }

    // Clear search and let it reset naturally
    searchQuery = ""
    items = all
    updateUnpinnedShortcuts()
    if item.isUnpinned {
      AppState.shared.scrollTarget = item.id
    }
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    // Use cached 'all' array instead of fetching from database
    let allItems = all.map(\.item)
    let duplicates = allItems.filter({ $0 == item || $0.supersedes(item) })
    if duplicates.count > 1 {
      return duplicates.first(where: { $0 != item })
    } else {
      return isModified(item)
    }
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  private func updateShortcuts() {
    for item in pinnedItems {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  private func updateUnpinnedShortcuts() {
    let visibleUnpinnedItems = unpinnedItems.filter(\.isVisible)
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(10) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
