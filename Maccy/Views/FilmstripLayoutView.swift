import Defaults
import SwiftUI

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
