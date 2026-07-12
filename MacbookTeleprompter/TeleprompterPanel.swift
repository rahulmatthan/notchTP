import AppKit
import SwiftUI

class TeleprompterPanel: NSPanel {

    private var viewModel: TeleprompterViewModel
    private var onSettingsTapped: () -> Void
    private var onClose: () -> Void
    private var scrollMonitor: Any?

    init(
        viewModel: TeleprompterViewModel,
        onSettingsTapped: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSettingsTapped = onSettingsTapped
        self.onClose = onClose

        let (origin, size) = TeleprompterPanel.calculateFrame()

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configure()
        setupContentView()
        setupScrollMonitor()
    }

    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Frame Calculation

    static func calculateFrame() -> (CGPoint, CGSize) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let safeTop = screen.safeAreaInsets.top   // ~32pt notched, 0 otherwise
        let winW: CGFloat = TeleprompterLayout.panelWidth
        let winH: CGFloat = TeleprompterLayout.panelHeight
        let x = (screen.frame.width - winW) / 2

        let y: CGFloat
        if safeTop > 0 {
            // Notched Mac: top edge flush with the physical top of the screen.
            // The window sits right where the notch is — pure black background merges with it.
            y = screen.frame.height - winH
        } else {
            // Non-notched Mac: position just below the menu bar as before.
            let menuBar = NSStatusBar.system.thickness
            y = screen.frame.height - menuBar - winH
        }

        return (CGPoint(x: x, y: y), CGSize(width: winW, height: winH))
    }

    // MARK: - Configuration

    private func configure() {
        level = .statusBar          // above mainMenu level — renders over the menu bar
        backgroundColor = .clear    // SwiftUI content paints its own black; transparent elsewhere
        isOpaque = false            // required for the emerge-from-notch clip animation
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    private func setupContentView() {
        let cv = NSHostingView(
            rootView: TeleprompterView(
                viewModel: viewModel,
                onSettingsTapped: onSettingsTapped,
                onClose: onClose
            )
        )
        cv.frame = NSRect(origin: .zero, size: frame.size)
        self.contentView = cv
    }

    // MARK: - Scroll Monitor

    private func setupScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            self.viewModel.adjustScroll(by: event.scrollingDeltaY)
            return event
        }
    }

    // MARK: - NSPanel Overrides

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
