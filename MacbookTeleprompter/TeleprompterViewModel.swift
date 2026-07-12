import Foundation
import AppKit
import Combine

class TeleprompterViewModel: ObservableObject {

    @Published var text: String = ""
    @Published var segments: [ScriptSegment] = []
    @Published var scrollOffset: CGFloat = 0
    @Published var targetScrollOffset: CGFloat = 0
    @Published var isPlaying: Bool = false
    @Published var speed: Double = 40      // pts/sec, range 10–120
    @Published var fontSize: CGFloat = 18
    @Published var isDismissing: Bool = false   // true while close animation plays
    @Published var playbackMode: PlaybackMode = .autoScroll
    @Published var trackingState: TrackingState = .auto
    @Published var speechStatusText: String = "Voice follow off"
    @Published var isListening: Bool = false
    @Published var speechConfidence: Double = 0
    @Published var currentAnchorIndex: Int = 0

    private var scrollTimer: Timer?
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var cancellables = Set<AnyCancellable>()
    private let speechService: SpeechTrackingServiceProtocol
    private var smoothedVoiceSpeed: Double?
    private var lastLockedAt: Date?
    private var lastSpeechHeardAt: Date?
    private var permissions = SpeechPermissions(microphoneGranted: false, speechGranted: false)
    private let recoveryTimeout: TimeInterval = 1.5
    private let contentWidth: CGFloat = TeleprompterLayout.panelWidth

    var formattedPermissionStatus: String {
        "\(permissions.statusText) [mic: \(permissions.microphoneGranted ? "on" : "off"), speech: \(permissions.speechGranted ? "on" : "off")]"
    }

    init(speechService: SpeechTrackingServiceProtocol = SpeechTrackingService()) {
        self.speechService = speechService
        self.permissions = speechService.currentPermissions()
        bindSpeechService()
        bindPlayback()
    }

    // MARK: - Bindings

    private func bindSpeechService() {
        speechService.onPermissionsChanged = { [weak self] permissions in
            DispatchQueue.main.async {
                self?.permissions = permissions
                self?.updateSpeechStatus()
            }
        }
        speechService.onTranscript = { [weak self] transcript in
            DispatchQueue.main.async {
                self?.handleTranscript(transcript)
            }
        }
        speechService.onError = { [weak self] message, fatal in
            DispatchQueue.main.async {
                self?.handleSpeechError(message, fatal: fatal)
            }
        }
    }

    private func bindPlayback() {
        $isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.handlePlaybackChange(playing)
            }
            .store(in: &cancellables)
    }

    private func handlePlaybackChange(_ playing: Bool) {
        if playing {
            startTimer()
            if playbackMode == .followVoice {
                startSpeechTrackingIfNeeded()
            }
        } else {
            stopTimer()
            stopSpeechTracking()
        }
    }

    // MARK: - Playback Control

    func togglePlayback() {
        isPlaying = !isPlaying
    }

    func reset() {
        stopPlaybackAndTracking()
        scrollOffset = 0
        targetScrollOffset = 0
        resetVoiceProgress()
        trackingState = playbackMode == .followVoice ? .recovering : .auto
    }

    func clearText() {
        stopPlaybackAndTracking()
        scrollOffset = 0
        targetScrollOffset = 0
        text = ""
        segments = []
        resetVoiceProgress()
        trackingState = .auto
        updateSpeechStatus()
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
        let effectiveSpeed = effectiveScrollSpeed()
        let shouldChaseTarget = playbackMode == .followVoice && !segments.isEmpty

        if shouldChaseTarget {
            let maxStep = CGFloat(max(effectiveSpeed * frameInterval, 2))
            let delta = targetScrollOffset - scrollOffset
            if abs(delta) <= maxStep {
                scrollOffset = max(0, targetScrollOffset)
            } else {
                scrollOffset += delta < 0 ? -maxStep : maxStep
            }
        } else {
            scrollOffset += CGFloat(effectiveSpeed * frameInterval)
        }

        if playbackMode == .followVoice, trackingState != .locked {
            targetScrollOffset = scrollOffset
            handleRecoveryTimeoutIfNeeded()
        }
    }

    // MARK: - Clipboard

    func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            applyNewText(string)
        }
    }

    // MARK: - Speed & Font Helpers

    func increaseSpeed() { speed = min(120, speed + 5) }
    func decreaseSpeed() { speed = max(10, speed - 5) }

    func increaseFontSize() {
        fontSize = min(40, fontSize + 2)
        rebuildSegments()
    }

    func decreaseFontSize() {
        fontSize = max(10, fontSize - 2)
        rebuildSegments()
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        if mode == .followVoice {
            trackingState = .recovering
            updateCurrentAnchorFromScroll()
            targetScrollOffset = scrollOffset
            updateSpeechStatus()
            startSpeechTrackingIfNeeded()
        } else {
            stopSpeechTracking()
            trackingState = .auto
            speechConfidence = 0
            targetScrollOffset = scrollOffset
            speechStatusText = "Standard auto scroll"
        }
    }

    func startSpeechTrackingIfNeeded() {
        guard playbackMode == .followVoice else { return }
        guard !isListening else { return }
        guard !segments.isEmpty else {
            speechStatusText = "Paste a script to use Follow Voice"
            return
        }

        Task { [weak self] in
            guard let self else { return }

            let permissions = await self.speechService.requestPermissions()
            guard permissions.granted else {
                await MainActor.run {
                    self.applyPermissions(permissions)
                    self.transitionToPermissionFailure()
                }
                return
            }

            do {
                try self.speechService.start()
                await MainActor.run {
                    self.applyPermissions(permissions)
                    self.isListening = true
                    self.trackingState = .recovering
                    self.lastSpeechHeardAt = Date()
                    self.updateSpeechStatus()
                }
            } catch {
                await MainActor.run {
                    self.handleSpeechError(error.localizedDescription, fatal: false)
                }
            }
        }
    }

    func stopSpeechTracking() {
        speechService.stop()
        isListening = false
        if playbackMode == .followVoice {
            updateSpeechStatus()
        }
    }

    func resyncToVisiblePosition() {
        updateCurrentAnchorFromScroll()
        trackingState = .recovering
        targetScrollOffset = anchorOffset(for: currentAnchorIndex)
        lastLockedAt = nil
        updateSpeechStatus()
    }

    func adjustScroll(by delta: CGFloat, resumeDelay: TimeInterval = 0.5) {
        let wasPlaying = isPlaying
        if wasPlaying { isPlaying = false }
        scrollOffset = max(0, scrollOffset - delta)
        targetScrollOffset = scrollOffset
        updateCurrentAnchorFromScroll()

        if playbackMode == .followVoice {
            trackingState = .recovering
            updateSpeechStatus()
        }

        if wasPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + resumeDelay) { [weak self] in
                self?.isPlaying = true
            }
        }
    }

    func nudgeUp() {
        adjustScroll(by: 20, resumeDelay: 0)
    }

    func nudgeDown() {
        adjustScroll(by: -20, resumeDelay: 0)
    }

    func updateText(_ newText: String) {
        applyNewText(newText)
    }

    func refreshLayoutPreservingPosition() {
        let previousAnchor = currentAnchorIndex
        rebuildSegments()
        currentAnchorIndex = min(previousAnchor, max(segments.count - 1, 0))
        targetScrollOffset = anchorOffset(for: currentAnchorIndex)
        scrollOffset = targetScrollOffset
    }

    private func rebuildSegments() {
        segments = ScriptProcessing.buildSegments(
            from: text,
            fontSize: fontSize,
            contentWidth: contentWidth
        )
        targetScrollOffset = anchorOffset(for: currentAnchorIndex)
    }

    private func handleTranscript(_ transcript: String) {
        lastSpeechHeardAt = Date()
        updateSpeechStatus(transcriptSeen: true)

        guard playbackMode == .followVoice, !segments.isEmpty else { return }

        guard let match = ScriptProcessing.bestMatch(
            transcript: transcript,
            in: segments,
            anchorIndex: currentAnchorIndex,
            lastLockedAt: lastLockedAt,
            currentOffset: scrollOffset
        ) else {
            trackingState = .recovering
            speechConfidence = max(0.15, speechConfidence * 0.85)
            updateSpeechStatus()
            return
        }

        currentAnchorIndex = max(currentAnchorIndex, match.segmentIndex)
        targetScrollOffset = anchorOffset(for: currentAnchorIndex)
        speechConfidence = match.confidence
        trackingState = .locked

        if let inferred = match.inferredPointsPerSecond, inferred.isFinite {
            let bounded = min(140, max(15, inferred))
            smoothedVoiceSpeed = smoothedVoiceSpeed.map { $0 * 0.75 + bounded * 0.25 } ?? bounded
        }

        lastLockedAt = Date()
        updateSpeechStatus()
    }

    private func handleSpeechError(_ message: String, fatal: Bool) {
        isListening = false
        trackingState = fatal ? .unavailable : .recovering
        speechStatusText = message
    }

    private func updateSpeechStatus(transcriptSeen: Bool = false) {
        guard playbackMode == .followVoice else {
            speechStatusText = "Voice follow off"
            return
        }

        if !permissions.granted {
            speechStatusText = formattedPermissionStatus
            return
        }

        switch trackingState {
        case .auto:
            speechStatusText = "Fallback scroll"
        case .locked:
            speechStatusText = "Tracking"
        case .recovering:
            speechStatusText = transcriptSeen || isListening ? "Recovering" : "Listening"
        case .unavailable:
            speechStatusText = "Speech unavailable"
        }
    }

    private func handleRecoveryTimeoutIfNeeded() {
        guard playbackMode == .followVoice else { return }
        guard let lastSpeechHeardAt else {
            trackingState = .recovering
            return
        }

        if Date().timeIntervalSince(lastSpeechHeardAt) > recoveryTimeout {
            trackingState = .auto
            speechConfidence = max(0.05, speechConfidence * 0.9)
            updateSpeechStatus()
        }
    }

    private func effectiveScrollSpeed() -> Double {
        if playbackMode == .followVoice {
            return smoothedVoiceSpeed ?? speed
        }
        return speed
    }

    private func anchorOffset(for index: Int) -> CGFloat {
        guard segments.indices.contains(index) else { return scrollOffset }
        let anchorY = TeleprompterLayout.panelHeight * TeleprompterLayout.textAnchorRatio
        return max(0, segments[index].topOffset - anchorY)
    }

    private func updateCurrentAnchorFromScroll() {
        guard !segments.isEmpty else {
            currentAnchorIndex = 0
            return
        }

        let anchorY = scrollOffset + TeleprompterLayout.panelHeight * TeleprompterLayout.textAnchorRatio
        let index = segments.lastIndex(where: { $0.topOffset <= anchorY }) ?? 0
        currentAnchorIndex = index
    }

    private func applyNewText(_ newText: String) {
        text = newText
        rebuildSegments()
        reset()
    }

    private func applyPermissions(_ permissions: SpeechPermissions) {
        self.permissions = permissions
    }

    private func transitionToPermissionFailure() {
        isListening = false
        trackingState = .unavailable
        speechStatusText = formattedPermissionStatus
    }

    private func stopPlaybackAndTracking() {
        isPlaying = false
        stopSpeechTracking()
    }

    private func resetVoiceProgress() {
        currentAnchorIndex = 0
        speechConfidence = 0
        smoothedVoiceSpeed = nil
        lastLockedAt = nil
        lastSpeechHeardAt = nil
    }
}
