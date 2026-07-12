import Foundation
import AppKit
import AVFoundation
import AVFAudio
import Speech

struct ScriptSegment: Identifiable, Equatable {
    let id: Int
    let text: String
    let normalizedTokens: [String]
    let estimatedHeight: CGFloat
    let topOffset: CGFloat
}

struct MatchResult {
    let segmentIndex: Int
    let confidence: Double
    let inferredPointsPerSecond: Double?
}

enum TrackingState: Equatable {
    case auto
    case locked
    case recovering
    case unavailable
}

enum PlaybackMode: String, CaseIterable, Identifiable {
    case autoScroll
    case followVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoScroll: return "Auto Scroll"
        case .followVoice: return "Follow Voice"
        }
    }
}

struct SpeechPermissions {
    let microphoneGranted: Bool
    let speechGranted: Bool

    var granted: Bool {
        microphoneGranted && speechGranted
    }

    var statusText: String {
        switch (microphoneGranted, speechGranted) {
        case (false, false):
            return "Microphone and speech permission needed"
        case (false, true):
            return "Microphone permission needed"
        case (true, false):
            return "Speech permission needed"
        case (true, true):
            return "Ready"
        }
    }
}

protocol SpeechTrackingServiceProtocol: AnyObject {
    var onPermissionsChanged: ((SpeechPermissions) -> Void)? { get set }
    var onTranscript: ((String) -> Void)? { get set }
    var onError: ((String, Bool) -> Void)? { get set }

    func currentPermissions() -> SpeechPermissions
    func requestMicrophonePermissionOnly() async -> Bool
    func requestPermissions() async -> SpeechPermissions
    func start() throws
    func stop()
}

final class SpeechTrackingService: NSObject, SpeechTrackingServiceProtocol, @unchecked Sendable {
    var onPermissionsChanged: ((SpeechPermissions) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onError: ((String, Bool) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRunning = false

    func currentPermissions() -> SpeechPermissions {
        let microphoneGranted: Bool
        if #available(macOS 14.0, *) {
            microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            microphoneGranted = false
        }

        let speechGranted: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechGranted = true
        default:
            speechGranted = false
        }

        return SpeechPermissions(
            microphoneGranted: microphoneGranted,
            speechGranted: speechGranted
        )
    }

    func requestMicrophonePermissionOnly() async -> Bool {
        await prepareForPermissionPrompt()

        let granted = await requestMicrophonePermission()
        let permissions = SpeechPermissions(
            microphoneGranted: granted,
            speechGranted: currentPermissions().speechGranted
        )

        await MainActor.run {
            self.onPermissionsChanged?(permissions)
        }
        await restoreAccessoryActivationIfNeeded()

        return granted
    }

    func requestPermissions() async -> SpeechPermissions {
        await prepareForPermissionPrompt()

        let microphoneGranted = await requestMicrophonePermission()
        let speechGranted = await requestSpeechPermission()
        let permissions = SpeechPermissions(
            microphoneGranted: microphoneGranted,
            speechGranted: speechGranted
        )

        await MainActor.run {
            self.onPermissionsChanged?(permissions)
        }
        await restoreAccessoryActivationIfNeeded()
        return permissions
    }

    func start() throws {
        guard recognizer?.isAvailable == true else {
            throw SpeechTrackingError.recognizerUnavailable
        }

        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.onTranscript?(result.bestTranscription.formattedString)
            }

            if let error {
                let isFatal = !self.isRunning
                self.onError?(error.localizedDescription, isFatal)
            }

            if result?.isFinal == true {
                self.restartIfNeeded()
            }
        }
    }

    func stop() {
        guard isRunning || recognitionTask != nil || recognitionRequest != nil else { return }

        isRunning = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func restartIfNeeded() {
        guard isRunning else { return }

        do {
            try start()
        } catch {
            onError?(error.localizedDescription, false)
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        let initialPermission: Bool
        if #available(macOS 14.0, *) {
            initialPermission = AVAudioApplication.shared.recordPermission == .granted
        } else {
            initialPermission = false
        }

        if initialPermission {
            return true
        }

        return await withCheckedContinuation { continuation in
            if #available(macOS 14.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .granted:
                    continuation.resume(returning: true)
                case .denied:
                    continuation.resume(returning: false)
                case .undetermined:
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                @unknown default:
                    continuation.resume(returning: false)
                }
            } else {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    @MainActor
    private func prepareForPermissionPrompt() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func restoreAccessoryActivationIfNeeded() {
        NSApp.setActivationPolicy(.accessory)
    }
}

enum SpeechTrackingError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable on this Mac right now."
        }
    }
}

enum ScriptProcessing {
    static func buildSegments(
        from text: String,
        fontSize: CGFloat,
        contentWidth: CGFloat
    ) -> [ScriptSegment] {
        let phrases = splitIntoSegments(text)
        guard !phrases.isEmpty else { return [] }

        let availableWidth = max(180, contentWidth - 32)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 6

        var currentTop: CGFloat = 0
        return phrases.enumerated().map { index, phrase in
            let estimatedHeight = heightForSegment(
                phrase,
                width: availableWidth,
                font: font,
                paragraphStyle: paragraph
            )
            defer { currentTop += estimatedHeight + 12 }

            return ScriptSegment(
                id: index,
                text: phrase,
                normalizedTokens: normalizeTokens(in: phrase),
                estimatedHeight: estimatedHeight,
                topOffset: currentTop
            )
        }
    }

    static func splitIntoSegments(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let segments = normalized
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return [] }

                let parts = trimmed.split(
                    whereSeparator: { [".", "!", "?", ";", ":"].contains($0) }
                )
                let phrases = parts
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .flatMap { chunkPhrase($0, maxWords: 5) }

                return phrases.isEmpty ? chunkPhrase(trimmed, maxWords: 5) : phrases
            }

        return segments
    }

    static func normalizeTokens(in text: String) -> [String] {
        text
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9\\s']",
                with: " ",
                options: .regularExpression
            )
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func bestMatch(
        transcript: String,
        in segments: [ScriptSegment],
        anchorIndex: Int,
        lastLockedAt: Date?,
        currentOffset: CGFloat
    ) -> MatchResult? {
        let transcriptTokens = normalizeTokens(in: transcript)
        guard transcriptTokens.count >= 2 else { return nil }

        let searchStart = max(0, anchorIndex - 1)
        let searchEnd = min(segments.count - 1, anchorIndex + 6)
        guard searchStart <= searchEnd else { return nil }

        var bestIndex: Int?
        var bestScore = 0.0

        for index in searchStart...searchEnd {
            let segmentTokens = segments[index].normalizedTokens
            guard !segmentTokens.isEmpty else { continue }

            let overlap = overlapScore(transcriptTokens, segmentTokens)
            let proximityPenalty = Double(index - anchorIndex) * 0.04
            let score = overlap - proximityPenalty
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        guard let segmentIndex = bestIndex, bestScore >= 0.34 else {
            return nil
        }

        var inferredPace: Double?
        if let lastLockedAt {
            let elapsed = Date().timeIntervalSince(lastLockedAt)
            if elapsed > 0.25 {
                let delta = max(0, segments[segmentIndex].topOffset - currentOffset)
                inferredPace = Double(delta / CGFloat(elapsed))
            }
        }

        return MatchResult(
            segmentIndex: segmentIndex,
            confidence: min(bestScore, 0.95),
            inferredPointsPerSecond: inferredPace
        )
    }

    private static func overlapScore(_ transcript: [String], _ segment: [String]) -> Double {
        let transcriptSet = Set(transcript)
        let segmentSet = Set(segment)
        let common = transcriptSet.intersection(segmentSet).count
        let base = Double(common) / Double(max(segmentSet.count, 1))

        if transcript.count >= segment.count, transcript.suffix(segment.count).elementsEqual(segment) {
            return max(base, 0.9)
        }

        let sequenceBonus = longestOrderedOverlap(transcript, segment)
        return min(1.0, base * 0.7 + sequenceBonus * 0.3)
    }

    private static func longestOrderedOverlap(_ transcript: [String], _ segment: [String]) -> Double {
        guard !segment.isEmpty else { return 0 }

        var best = 0
        for start in 0..<transcript.count {
            var matched = 0
            var t = start
            var s = 0

            while t < transcript.count && s < segment.count {
                if transcript[t] == segment[s] {
                    matched += 1
                    s += 1
                }
                t += 1
            }

            best = max(best, matched)
        }

        return Double(best) / Double(segment.count)
    }

    private static func heightForSegment(
        _ text: String,
        width: CGFloat,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )

        let rect = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 16
    }

    private static func chunkPhrase(_ phrase: String, maxWords: Int) -> [String] {
        let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > maxWords else { return [phrase] }

        var chunks: [String] = []
        var index = 0

        while index < words.count {
            let end = min(index + maxWords, words.count)
            let chunk = words[index..<end].joined(separator: " ")
            chunks.append(chunk)
            index = end
        }

        return chunks
    }
}
