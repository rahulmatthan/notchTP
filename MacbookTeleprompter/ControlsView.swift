import SwiftUI

// MARK: - Settings flyout content (formerly ControlsView)

struct SettingsView: View {
    @ObservedObject var viewModel: TeleprompterViewModel
    let onClose: () -> Void       // closes entire teleprompter
    let onDismiss: () -> Void     // closes just this flyout

    private let charcoal = Color(red: 0.13, green: 0.13, blue: 0.15)

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                SettingsIconButton(icon: "xmark", size: 9, action: onDismiss)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 8) {

                // Paste
                SettingsRowButton(icon: "doc.on.clipboard", label: "Paste Script") {
                    viewModel.pasteFromClipboard()
                    onDismiss()
                }

                // Playback row
                HStack(spacing: 8) {
                    SettingsIconButton(
                        icon: viewModel.isPlaying ? "pause.fill" : "play.fill",
                        action: viewModel.togglePlayback
                    )
                    SettingsIconButton(icon: "backward.end.fill", action: viewModel.reset)
                    Spacer()
                    Text(viewModel.isPlaying ? "Playing" : "Paused")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }

                // Speed slider
                VStack(spacing: 3) {
                    HStack {
                        Text("Speed")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Text("\(Int(viewModel.speed)) pt/s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Slider(value: $viewModel.speed, in: 10...120, step: 5)
                        .tint(.white.opacity(0.55))
                }

                // Font size slider
                VStack(spacing: 3) {
                    HStack {
                        Text("Font size")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Text("\(Int(viewModel.fontSize)) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Slider(value: $viewModel.fontSize, in: 10...40, step: 2)
                        .tint(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Spacer()

            Divider().overlay(Color.white.opacity(0.08))

            // Close teleprompter button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                    Text("Close Teleprompter")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.red.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(charcoal.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

// MARK: - Helper: full-width row button

struct SettingsRowButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(.white.opacity(hovered ? 0.9 : 0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(hovered ? 0.10 : 0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Helper: icon-only square button

struct SettingsIconButton: View {
    let icon: String
    var size: CGFloat = 13
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(hovered ? 0.9 : 0.55))
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(hovered ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
