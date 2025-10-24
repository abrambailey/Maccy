import Defaults
import SwiftUI

// MARK: - Horizontal Scroll Wheel Handler

private extension NSView {
  func isDescended(from cls: AnyClass) -> Bool {
    var v: NSView? = self
    while let cur = v {
      if cur.isKind(of: cls) { return true }
      v = cur.superview
    }
    return false
  }
}

struct ScrollWheelHandlerView: NSViewRepresentable {
  func makeNSView(context: Context) -> ScrollWheelCaptureView {
    let view = ScrollWheelCaptureView()
    return view
  }

  func updateNSView(_ nsView: ScrollWheelCaptureView, context: Context) {}

  static func dismantleNSView(_ nsView: ScrollWheelCaptureView, coordinator: ()) {
    nsView.removeEventMonitor()
  }
}

class ScrollWheelCaptureView: NSView {
  private var eventMonitor: Any?
  private let logFile: URL = {
    let tempDir = FileManager.default.temporaryDirectory
    return tempDir.appendingPathComponent("maccy_scroll_debug.log")
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // Clear log file on init
    try? "=== Maccy Scroll Debug Log ===\n".write(to: logFile, atomically: true, encoding: .utf8)
    log("Log file created at: \(logFile.path)")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func log(_ message: String) {
    let timestamp = Date()
    let logMessage = "[\(timestamp)] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: logFile) {
      handle.seekToEndOfFile()
      if let data = logMessage.data(using: .utf8) {
        handle.write(data)
      }
      try? handle.close()
    } else {
      try? logMessage.write(to: logFile, atomically: false, encoding: .utf8)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      log("View moved to window, installing event monitor")
      installEventMonitor()
    } else {
      log("View removed from window, removing event monitor")
      removeEventMonitor()
    }
  }

  deinit {
    log("View deallocating, removing event monitor")
    removeEventMonitor()
  }

  private func installEventMonitor() {
    guard eventMonitor == nil else {
      log("Event monitor already installed, skipping")
      return
    }

    log("Installing event monitor for scroll wheel events")

    // Must be retained strongly
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
      guard let self, let win = self.window, let root = win.contentView else { return event }

      // Bounds gate (self coords)
      let pInSelf = self.convert(event.locationInWindow, from: nil)

      // DEBUG: Log bounds and position
      self.log("📍 Scroll event - pInSelf: \(pInSelf), bounds: \(self.bounds), contains: \(self.bounds.contains(pInSelf))")

      guard self.bounds.contains(pInSelf) else {
        self.log("❌ Outside bounds, passing through")
        return event
      }

      // Proper hit-test coords (CRITICAL: convert to root's coordinate system!)
      let pInRoot = root.convert(event.locationInWindow, from: nil)
      let hit = root.hitTest(pInRoot)

      // Pass through only if the nearest scroll view isn't our filmstrip's
      let svUnderPointer = self.nearestScrollView(from: hit)
      let filmstripSV = self.findHorizontalScrollView()

      // DEBUG: Log scroll view comparison
      if let svUnderPointer {
        self.log("🔍 HIT SV: \(svUnderPointer === filmstripSV ? "filmstrip" : "nested")")
      } else {
        self.log("🔍 HIT SV: none")
      }

      if let svUnderPointer, let filmstripSV, svUnderPointer !== filmstripSV {
        self.log("⤴️ Passing through to nested scroller")
        return event
      }

      // Get correct vertical delta (CRITICAL: different for trackpad vs mouse!)
      let dy: CGFloat = event.hasPreciseScrollingDeltas
        ? CGFloat(event.scrollingDeltaY)   // high-resolution trackpad
        : CGFloat(event.deltaY)            // mouse wheel (lines)

      self.log("📊 dy: \(dy), precise: \(event.hasPreciseScrollingDeltas)")

      guard dy != 0 else {
        self.log("⚠️ dy is 0, ignoring")
        return event
      }

      // Momentum-aware scaling (use the event parameter, not NSApp.currentEvent!)
      let isMomentum = event.momentumPhase != []
      let scale: CGFloat = isMomentum ? 0.5 : 1.0

      self.log("➡️ Scrolling horizontally by: \(dy * scale)")
      self.scrollHorizontally(by: dy * scale)

      return nil
    }
  }

  func removeEventMonitor() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
  }

  private func nearestScrollView(from view: NSView?) -> NSScrollView? {
    var v = view
    while let cur = v {
      if let sv = cur as? NSScrollView { return sv }
      v = cur.superview
    }
    return nil
  }

  private func scrollHorizontally(by delta: CGFloat) {
    guard let sv = findHorizontalScrollView() else {
      log("❌ No horizontal scroll view found")
      return
    }

    // Ensure layout is up-to-date
    sv.layoutSubtreeIfNeeded()

    guard let doc = sv.documentView else {
      log("❌ No document view")
      return
    }

    let current = sv.contentView.bounds.origin
    // Use frame.width for accurate overflow calculation
    let maxX = max(0, doc.frame.width - sv.contentView.bounds.width)

    log("📏 Scroll calc - current.x: \(current.x), maxX: \(maxX), doc.frame.width: \(doc.frame.width), clipView.width: \(sv.contentView.bounds.width)")

    // Nothing to scroll if no horizontal overflow
    guard maxX > 0 else {
      log("❌ No horizontal overflow to scroll")
      return
    }

    let newX = min(max(current.x + delta, 0), maxX)

    log("🎯 Attempting scroll from \(current.x) to \(newX)")

    // Only scroll if position actually changed
    guard newX != current.x else {
      log("⚠️ No position change needed")
      return
    }

    // Prefer scroll(to:) over setBoundsOrigin
    sv.contentView.scroll(to: NSPoint(x: newX, y: current.y))
    sv.reflectScrolledClipView(sv.contentView)
    log("✅ Scrolled to \(newX)")
  }

  private func findHorizontalScrollView() -> NSScrollView? {
    var currentView: NSView? = self.superview
    while let view = currentView {
      if let scrollView = view as? NSScrollView {
        return scrollView
      }
      currentView = view.superview
    }
    return nil
  }
}

// MARK: - Filmstrip Mask

struct FilmstripMask: Shape {
  func path(in rect: CGRect) -> Path {
    let scrollBarHeight: CGFloat = 14
    let cornerRadius: CGFloat = 8
    var path = Path()

    // Main content area with rounded corners
    let contentRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - scrollBarHeight)
    path.addRoundedRect(in: contentRect,
                        cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                        style: .continuous)

    // Scroll bar area as capsule
    let scrollBarRect = CGRect(x: 0, y: rect.height - scrollBarHeight, width: rect.width, height: scrollBarHeight)
    path.addRoundedRect(in: scrollBarRect,
                        cornerSize: CGSize(width: scrollBarHeight / 2, height: scrollBarHeight / 2),
                        style: .continuous)

    return path
  }
}

struct FilmstripLayoutView: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.pinTo) private var pinTo
  @Default(.previewDelay) private var previewDelay

  private var pinnedItems: [HistoryItemDecorator] {
    appState.history.pinnedItems.filter(\.isVisible)
  }
  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }
  private var showPinsSeparator: Bool {
    !pinnedItems.isEmpty && !unpinnedItems.isEmpty && appState.history.searchQuery.isEmpty
  }

  // Calculate horizontal filmstrip layout
  private let cardWidth: CGFloat = 280
  private let cardHeight: CGFloat = 200
  private let spacing: CGFloat = 16
  private let padding: CGFloat = 20

  var body: some View {
    ScrollView(.horizontal) {
      ScrollViewReader { proxy in
        HStack(spacing: spacing) {
          // Pinned items section
          if !pinnedItems.isEmpty && pinTo == .top {
            pinnedItemsSection
          }

          // Unpinned items section (filmstrip horizontal)
          unpinnedItemsSection

          // Pinned items at bottom
          if !pinnedItems.isEmpty && pinTo == .bottom {
            pinnedItemsSection
          }
        }
        .padding(.horizontal, 5)
        .padding(.top, padding)
        .padding(.bottom, padding)
        .frame(height: cardHeight + (padding * 2))
        .task(id: appState.scrollTarget) {
          guard appState.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.scrollTarget {
            withAnimation(.easeInOut(duration: 0.3)) {
              proxy.scrollTo(selection, anchor: .center)
            }
            appState.scrollTarget = nil
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .active {
            searchFocused = true
            HistoryItemDecorator.previewThrottler.minimumDelay = Double(previewDelay) / 1000
            HistoryItemDecorator.previewThrottler.cancel()
            appState.isKeyboardNavigating = true
            appState.selection = appState.history.unpinnedItems.first?.id ?? appState.history.pinnedItems.first?.id
          } else {
            modifierFlags.flags = []
            appState.isKeyboardNavigating = true
          }
        }
        .background {
          GeometryReader { geo in
            Color.clear
              .task(id: appState.popup.needsResize) {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }

                if appState.popup.needsResize {
                  appState.popup.resize(height: geo.size.height)
                }
              }
          }
        }
      }
      .scrollIndicators(.visible, axes: .horizontal)
    }
    .background {
      Color.clear
        .padding(.bottom, 14)
    }
    .mask(FilmstripMask())
    .padding(.horizontal, 10)
  }

  @ViewBuilder
  private var pinnedItemsSection: some View {
    HStack(spacing: spacing) {
      filmstripRow(for: pinnedItems)
    }
  }

  @ViewBuilder
  private var unpinnedItemsSection: some View {
    filmstripRow(for: unpinnedItems)
  }

  @ViewBuilder
  private func filmstripRow(for items: [HistoryItemDecorator]) -> some View {
    ForEach(items) { item in
      HistoryCardView(item: item, searchQuery: searchQuery)
        .id(item.id)
        .transition(.scale.combined(with: .opacity))
    }
  }
}
