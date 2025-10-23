import Defaults
import SwiftUI

struct HeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @Default(.showTitle) private var showTitle
  @State private var localQuery: String = ""
  @State private var debounceTask: Task<Void, Never>?

  var body: some View {
    HStack {
      if showTitle {
        Text("Maccy")
          .foregroundStyle(.secondary)
      }

      SearchFieldView(placeholder: "search_placeholder", query: $localQuery)
        .focused($searchFocused)
        .frame(maxWidth: .infinity)
        .onChange(of: localQuery) { oldValue, newValue in
          debounceTask?.cancel()
          debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled {
              searchQuery = newValue
            }
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .background && !localQuery.isEmpty {
            localQuery = ""
            searchQuery = ""
          }
        }
    }
    .frame(height: appState.searchVisible ? 25 : 0)
    .opacity(appState.searchVisible ? 1 : 0)
    .padding(.horizontal, 10)
    // 2px is needed to prevent items from showing behind top pinned items during scrolling
    // https://github.com/p0deje/Maccy/issues/832
    .padding(.bottom, appState.searchVisible ? 5 : 2)
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.headerHeight = geo.size.height
          }
      }
    }
  }
}
