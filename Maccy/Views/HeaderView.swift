import Defaults
import SwiftUI

struct HeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @Default(.showTitle) private var showTitle
  @Default(.suppressClearAlert) private var suppressClearAlert
  @State private var localQuery: String = ""
  @State private var debounceTask: Task<Void, Never>?

  var body: some View {
    HStack {
      if showTitle {
        Menu {
          Button("clear") {
            Task { @MainActor in
              if !suppressClearAlert {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
                alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
                alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
                alert.showsSuppressionButton = true

                let response = alert.runModal()
                if alert.suppressionButton?.state == .on {
                  suppressClearAlert = true
                }

                if response == .alertFirstButtonReturn {
                  appState.history.clear()
                }
              } else {
                appState.history.clear()
              }
            }
          }

          Button("clear_all") {
            Task { @MainActor in
              if !suppressClearAlert {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
                alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
                alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
                alert.showsSuppressionButton = true

                let response = alert.runModal()
                if alert.suppressionButton?.state == .on {
                  suppressClearAlert = true
                }

                if response == .alertFirstButtonReturn {
                  appState.history.clearAll()
                }
              } else {
                appState.history.clearAll()
              }
            }
          }

          Divider()

          Button("preferences") {
            Task { @MainActor in
              appState.openPreferences()
            }
          }

          Button("about") {
            appState.openAbout()
          }

          Divider()

          Button("quit") {
            Task { @MainActor in
              appState.quit()
            }
          }
        } label: {
          Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
