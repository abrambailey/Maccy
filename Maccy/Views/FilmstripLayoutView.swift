import Defaults
import SwiftUI

// MARK: - Skeleton Card

struct SkeletonCardView: View {
  @State private var isAnimating = false

  private var cardWidth: CGFloat { 280 }
  private var cardHeight: CGFloat { 200 }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header skeleton
      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.gray.opacity(0.2))
          .frame(width: 16, height: 16)

        RoundedRectangle(cornerRadius: 4)
          .fill(Color.gray.opacity(0.2))
          .frame(width: 80, height: 12)

        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)

      // Content skeleton
      VStack(alignment: .leading, spacing: 6) {
        ForEach(0..<5) { _ in
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 10)
        }

        RoundedRectangle(cornerRadius: 3)
          .fill(Color.gray.opacity(0.15))
          .frame(width: cardWidth * 0.6, height: 10)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)

      Spacer()
    }
    .frame(width: cardWidth, height: cardHeight)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: .controlBackgroundColor))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    .opacity(isAnimating ? 0.5 : 1.0)
    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
    .onAppear {
      isAnimating = true
    }
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

  @State private var hasTriggeredLoad = false
  @State private var showSkeletons = false

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
        let _ = DispatchQueue.main.async {
          showSkeletons = true
        }
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
            hasTriggeredLoad = false
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
    .coordinateSpace(name: "scrollView")
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

    // Show skeleton placeholders if not fully loaded and not searching and we've shown them
    if !appState.history.isFullyLoaded && searchQuery.isEmpty && showSkeletons {
      skeletonCards
    }
  }

  @ViewBuilder
  private var skeletonCards: some View {
    ForEach(0..<7, id: \.self) { index in
      SkeletonCardView()
        .id("skeleton-\(index)")
        .background(
          GeometryReader { geo in
            Color.clear
              .onChange(of: geo.frame(in: .named("scrollView"))) { oldFrame, newFrame in
                let frame = newFrame
                print("MACCYDEBUG: skeleton[\(index)] frame.minX=\(frame.minX)")
                // Check if left edge of skeleton is within visible area (approximate screen width)
                if index == 0 && frame.minX < 1000 {
                  print("MACCYDEBUG: skeleton[\(index)] is in view, calling loadMoreItems()")
                  loadMoreItems()
                }
              }
          }
        )
        .frame(width: cardWidth, height: cardHeight)
    }
  }

  @ViewBuilder
  private func filmstripRow(for items: [HistoryItemDecorator]) -> some View {
    ForEach(items) { item in
      HistoryCardView(item: item, searchQuery: searchQuery)
        .id(item.id)
        .transition(.scale.combined(with: .opacity))
    }
  }

  private func loadMoreItems() {
    print("MACCYDEBUG: FilmstripLayoutView.loadMoreItems() called, isFullyLoaded=\(appState.history.isFullyLoaded), searchQuery='\(searchQuery)', hasTriggeredLoad=\(hasTriggeredLoad)")
    guard !appState.history.isFullyLoaded && searchQuery.isEmpty && !hasTriggeredLoad else {
      print("MACCYDEBUG: FilmstripLayoutView.loadMoreItems() - guard failed, returning")
      return
    }

    print("MACCYDEBUG: FilmstripLayoutView.loadMoreItems() - triggering load")
    hasTriggeredLoad = true
    Task {
      try? await appState.history.loadMoreItems()
      // Reset the flag so we can load again when scrolling to next batch
      hasTriggeredLoad = false
    }
  }
}
