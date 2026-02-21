import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var teleprompterPanel: TeleprompterPanel?
    private var settingsPanel: SettingsPanel?
    private var isSettingsVisible = false
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var dismissWork: DispatchWorkItem?   // cancellable close-animation timer
    let viewModel = TeleprompterViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupGlobalKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeMonitors()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Teleprompter")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc private func statusItemClicked() {
        if let panel = teleprompterPanel, panel.isVisible {
            closeAll()
        } else {
            openPanel()
        }
    }

    // MARK: - Panel Lifecycle

    func openPanel() {
        // Cancel any in-flight dismiss so a rapid reopen works cleanly
        dismissWork?.cancel()
        dismissWork = nil
        viewModel.isDismissing = false

        let panel = TeleprompterPanel(
            viewModel: viewModel,
            onSettingsTapped: { [weak self] in self?.toggleSettings() },
            onClose: { [weak self] in self?.closeAll() }
        )
        teleprompterPanel = panel
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        // Guard: don't start a second dismiss while one is already running
        guard !viewModel.isDismissing else { return }

        hideSettings()
        viewModel.isPlaying = false
        viewModel.isDismissing = true   // triggers reverse animation in TeleprompterView

        // Destroy the panel after the spring has settled (~1.0 s response + small buffer)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.isDismissing = false
            self.viewModel.scrollOffset = 0
            self.teleprompterPanel?.close()
            self.teleprompterPanel = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }

    // MARK: - Settings Panel

    func toggleSettings() {
        if isSettingsVisible {
            hideSettings()
        } else {
            showSettings()
        }
    }

    func showSettings() {
        guard let mainFrame = teleprompterPanel?.frame else { return }
        let panel = SettingsPanel(
            viewModel: viewModel,
            anchorFrame: mainFrame,
            onClose: { [weak self] in self?.closeAll() },
            onDismiss: { [weak self] in self?.hideSettings() }
        )
        settingsPanel = panel
        panel.orderFrontRegardless()
        isSettingsVisible = true
    }

    func hideSettings() {
        settingsPanel?.orderOut(nil)
        settingsPanel = nil
        isSettingsVisible = false
    }

    // MARK: - Key Monitors

    private func setupGlobalKeyMonitor() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = globalKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localKeyMonitor  { NSEvent.removeMonitor(monitor) }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard let panel = teleprompterPanel, panel.isVisible else { return }

        switch event.keyCode {
        case 49: // Space
            viewModel.togglePlayback()
        case 126: // Up arrow
            if viewModel.isPlaying {
                viewModel.speed = min(120, viewModel.speed + 5)
            } else {
                viewModel.scrollOffset = max(0, viewModel.scrollOffset - 20)
            }
        case 125: // Down arrow
            if viewModel.isPlaying {
                viewModel.speed = max(10, viewModel.speed - 5)
            } else {
                viewModel.scrollOffset += 20
            }
        case 53: // Escape
            if isSettingsVisible {
                hideSettings()
            } else {
                closeAll()
            }
        case 15: // R
            viewModel.reset()
        case 8: // C
            viewModel.clearText()
        default:
            if event.modifierFlags.contains(.command) && event.keyCode == 9 { // Cmd+V
                viewModel.pasteFromClipboard()
            }
        }
    }
}
