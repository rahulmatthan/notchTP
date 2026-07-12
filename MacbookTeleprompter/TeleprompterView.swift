import SwiftUI
import AppKit

struct TeleprompterView: View {
    @ObservedObject var viewModel: TeleprompterViewModel
    let onSettingsTapped: () -> Void
    let onClose: () -> Void

    @State private var gearHovered  = false
    @State private var closeHovered = false
    @State private var revealFraction: CGFloat = 0

    // Height of the notch (= safeAreaInsets.top on notched Macs, ~28pt fallback)
    private var notchHeight: CGFloat {
        let safe = NSScreen.main?.safeAreaInsets.top ?? 0
        return safe > 0 ? safe : 28
    }

    // Width of the camera island — derived from the areas flanking the notch
    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 162 }
        let left  = screen.auxiliaryTopLeftArea?.width  ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let computed = screen.frame.width - left - right
        return computed > 10 ? computed : 162   // fallback for non-notched Macs
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Top bar: ✕ ·· notch ·· ⚙ ──
            HStack(spacing: 0) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.85 : 0.30))
                        .frame(width: notchHeight, height: notchHeight)
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }

                Spacer()

                Button(action: onSettingsTapped) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(gearHovered ? 0.70 : 0.25))
                        .frame(width: notchHeight, height: notchHeight)
                }
                .buttonStyle(.plain)
                .onHover { gearHovered = $0 }
            }
            .frame(height: notchHeight)

            // ── Scrolling text ──
            ScrollableTextView(viewModel: viewModel)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.togglePlayback() }
        }
        .frame(width: TeleprompterLayout.panelWidth, height: TeleprompterLayout.panelHeight)
        .background(Color.black)
        // Expand outward from the notch centre
        .clipShape(EmergeShape(
            fraction:    revealFraction,
            notchWidth:  notchWidth,
            notchHeight: notchHeight
        ))
        .onAppear {
            withAnimation(.spring(response: 1.4, dampingFraction: 1.5)) {
                revealFraction = 1.0
            }
        }
        .onChange(of: viewModel.isDismissing) { dismissing in
            if dismissing {
                withAnimation(.spring(response: 1.0, dampingFraction: 1.2)) {
                    revealFraction = 0
                }
            }
        }
    }
}

// MARK: - Animatable shape: starts as notch rectangle, expands outward to full panel

struct EmergeShape: Shape {
    var fraction: CGFloat       // 0 = notch size centred, 1 = full 360×180 panel
    var notchWidth:  CGFloat    // starting width  (camera island width)
    var notchHeight: CGFloat    // starting height (safeAreaInsets.top)
    var bottomRadius: CGFloat = 10

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(1, fraction))

        // Interpolate size
        let w = notchWidth  + (rect.width  - notchWidth)  * f
        let h = notchHeight + (rect.height - notchHeight) * f

        // Centre the expanding shape horizontally (notch is in the centre of our window)
        let xMin = (rect.width - w) / 2
        let xMax = xMin + w
        let yMax = h        // top is always pinned to y = 0

        // Top corners: keep the same radius as the notch so they match at all times
        let tR: CGFloat = 8
        // Bottom corners: grow smoothly up to the final bottomRadius
        let bR = min(bottomRadius, h * 0.45)

        var path = Path()
        path.move(to: CGPoint(x: xMin + tR, y: 0))
        path.addLine(to: CGPoint(x: xMax - tR, y: 0))
        // Top-right convex corner: control point is outside the view so the curve
        // passes through the corner point (xMax, 0) rather than tucking inside it
        path.addQuadCurve(to: CGPoint(x: xMax,      y: tR),        control: CGPoint(x: xMax + tR / 2, y: -tR / 2))
        path.addLine(to: CGPoint(x: xMax,      y: yMax - bR))
        path.addQuadCurve(to: CGPoint(x: xMax - bR, y: yMax),      control: CGPoint(x: xMax, y: yMax))
        path.addLine(to: CGPoint(x: xMin + bR, y: yMax))
        path.addQuadCurve(to: CGPoint(x: xMin,      y: yMax - bR), control: CGPoint(x: xMin, y: yMax))
        path.addLine(to: CGPoint(x: xMin,      y: tR))
        // Top-left convex corner: same technique, mirrored
        path.addQuadCurve(to: CGPoint(x: xMin + tR, y: 0),         control: CGPoint(x: xMin - tR / 2, y: -tR / 2))
        path.closeSubpath()
        return path
    }
}

// MARK: - Scrollable Text Area

struct ScrollableTextView: View {
    @ObservedObject var viewModel: TeleprompterViewModel

    var body: some View {
        GeometryReader { geo in
            if viewModel.text.isEmpty {
                VStack {
                    Spacer()
                    Text("⚙ paste script\nSpace play/pause · R reset · C clear")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.28))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(width: geo.size.width)
            } else {
                ZStack(alignment: .top) {
                    VStack(spacing: 12) {
                        ForEach(viewModel.segments) { segment in
                            Text(segment.text)
                                .font(.system(size: viewModel.fontSize, weight: .medium))
                                .foregroundColor(segment.id == viewModel.currentAnchorIndex ? .white : .white.opacity(0.78))
                                .lineSpacing(6)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(width: geo.size.width, alignment: .top)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(segment.id == viewModel.currentAnchorIndex ? Color.white.opacity(0.08) : .clear)
                                )
                        }
                    }
                    .offset(y: -viewModel.scrollOffset)
                }
            }
        }
        .clipped()
    }
}

// MARK: - Custom Shape: flat top, rounded bottom (used by SettingsPanel background)

struct RoundedCornerShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = CGPoint(x: rect.minX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)

        path.move(to: CGPoint(x: tl.x + topRadius, y: tl.y))
        path.addLine(to: CGPoint(x: tr.x - topRadius, y: tr.y))
        path.addQuadCurve(to: CGPoint(x: tr.x, y: tr.y + topRadius), control: tr)
        path.addLine(to: CGPoint(x: br.x, y: br.y - bottomRadius))
        path.addQuadCurve(to: CGPoint(x: br.x - bottomRadius, y: br.y), control: br)
        path.addLine(to: CGPoint(x: bl.x + bottomRadius, y: bl.y))
        path.addQuadCurve(to: CGPoint(x: bl.x, y: bl.y - bottomRadius), control: bl)
        path.addLine(to: CGPoint(x: tl.x, y: tl.y + topRadius))
        path.addQuadCurve(to: CGPoint(x: tl.x + topRadius, y: tl.y), control: tl)
        path.closeSubpath()
        return path
    }
}
