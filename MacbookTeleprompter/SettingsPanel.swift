import AppKit
import SwiftUI

class SettingsPanel: NSPanel {

    init(
        viewModel: TeleprompterViewModel,
        anchorFrame: NSRect,
        onClose: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let w: CGFloat = 220
        let h: CGFloat = 260
        // Position: right of main window, tops aligned
        let x = anchorFrame.maxX + 6
        let y = anchorFrame.maxY - h

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let hostingView = NSHostingView(
            rootView: SettingsView(
                viewModel: viewModel,
                onClose: onClose,
                onDismiss: onDismiss
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: CGSize(width: w, height: h))
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
