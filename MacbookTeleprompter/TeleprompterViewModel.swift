import Foundation
import AppKit
import Combine

class TeleprompterViewModel: ObservableObject {

    @Published var text: String = ""
    @Published var scrollOffset: CGFloat = 0
    @Published var isPlaying: Bool = false
    @Published var speed: Double = 40      // pts/sec, range 10–120
    @Published var fontSize: CGFloat = 18
    @Published var isDismissing: Bool = false   // true while close animation plays

    private var scrollTimer: Timer?
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var cancellables = Set<AnyCancellable>()

    init() {
        $isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                guard let self = self else { return }
                if playing {
                    self.startTimer()
                } else {
                    self.stopTimer()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Control

    func togglePlayback() {
        isPlaying = !isPlaying
    }

    func reset() {
        isPlaying = false
        scrollOffset = 0
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        scrollTimer = Timer.scheduledTimer(
            timeInterval: frameInterval,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(scrollTimer!, forMode: .common)
    }

    private func stopTimer() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    @objc private func tick() {
        scrollOffset += CGFloat(speed * frameInterval)
    }

    // MARK: - Clipboard

    func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            text = string
            reset()
        }
    }

    // MARK: - Speed & Font Helpers

    func increaseSpeed() { speed = min(120, speed + 5) }
    func decreaseSpeed() { speed = max(10, speed - 5) }
    func increaseFontSize() { fontSize = min(40, fontSize + 2) }
    func decreaseFontSize() { fontSize = max(10, fontSize - 2) }
}
