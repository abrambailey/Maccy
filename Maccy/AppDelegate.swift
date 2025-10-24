import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>!

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy { History.shared.add($0) }
    Clipboard.shared.start()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  private func migrateUserDefaults() {
    if Defaults[.migrations]["2024-07-01-version-2"] != true {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      // Right-click shows menu
      if event.type == .rightMouseUp {
        showStatusItemMenu()
        return
      }

      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  private func showStatusItemMenu() {
    let menu = NSMenu()

    // Clear
    let clearItem = NSMenuItem(
      title: NSLocalizedString("clear", comment: "Clear menu item"),
      action: #selector(performClear),
      keyEquivalent: ""
    )
    clearItem.target = self
    menu.addItem(clearItem)

    // Clear All
    let clearAllItem = NSMenuItem(
      title: NSLocalizedString("clear_all", comment: "Clear All menu item"),
      action: #selector(performClearAll),
      keyEquivalent: ""
    )
    clearAllItem.target = self
    menu.addItem(clearAllItem)

    menu.addItem(NSMenuItem.separator())

    // Preferences
    let preferencesItem = NSMenuItem(
      title: NSLocalizedString("preferences", comment: "Preferences menu item"),
      action: #selector(performPreferences),
      keyEquivalent: ""
    )
    preferencesItem.target = self
    menu.addItem(preferencesItem)

    // About
    let aboutItem = NSMenuItem(
      title: NSLocalizedString("about", comment: "About menu item"),
      action: #selector(performAbout),
      keyEquivalent: ""
    )
    aboutItem.target = self
    menu.addItem(aboutItem)

    menu.addItem(NSMenuItem.separator())

    // Quit
    let quitItem = NSMenuItem(
      title: NSLocalizedString("quit", comment: "Quit menu item"),
      action: #selector(performQuit),
      keyEquivalent: ""
    )
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  @objc
  private func performAbout() {
    Task { @MainActor in
      AppState.shared.openAbout()
    }
  }

  @objc
  private func performPreferences() {
    Task { @MainActor in
      AppState.shared.openPreferences()
    }
  }

  @objc
  private func performQuit() {
    Task { @MainActor in
      AppState.shared.quit()
    }
  }

  @objc
  private func performClear() {
    Task { @MainActor in
      // Show confirmation if needed
      if !Defaults[.suppressClearAlert] {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
        alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
        alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
        alert.showsSuppressionButton = true

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
          Defaults[.suppressClearAlert] = true
        }

        if response == .alertFirstButtonReturn {
          AppState.shared.history.clear()
        }
      } else {
        AppState.shared.history.clear()
      }
    }
  }

  @objc
  private func performClearAll() {
    Task { @MainActor in
      // Show confirmation if needed
      if !Defaults[.suppressClearAlert] {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
        alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
        alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
        alert.showsSuppressionButton = true

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
          Defaults[.suppressClearAlert] = true
        }

        if response == .alertFirstButtonReturn {
          AppState.shared.history.clearAll()
        }
      } else {
        AppState.shared.history.clearAll()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
