import AVFoundation
import Observation
import Speech

/// Nhập bằng giọng nói: thu âm và nhận dạng tiếng Việt, ưu tiên xử lý ngay trên máy.
/// Chỉ trả về chữ; việc đổi số đọc bằng chữ thành chữ số do `SpokenNumbers` làm.
@MainActor @Observable
final class VoiceInput {
    enum State: Equatable {
        case idle
        case listening
        /// Chưa được cấp quyền micro hoặc nhận dạng giọng nói.
        case denied
        /// Máy chưa nhận dạng được tiếng Việt, hoặc đã có lỗi khi thu âm.
        case unavailable
    }

    private(set) var state: State = .idle
    /// Chữ nhận dạng được của lần nói hiện tại, cập nhật liên tục.
    private(set) var transcript = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// Tăng mỗi lần bắt đầu nói. Phản hồi muộn của phiên cũ (kể cả lỗi do hủy) không được tác động phiên mới.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?

    /// Tự dừng khi im lặng: chờ lâu hơn ở lúc chưa nói gì, ngắn hơn khi đã có chữ.
    static let waitForSpeech: Duration = .seconds(8)
    static let silenceAfterSpeech: Duration = .milliseconds(2_200)

    /// Thiếu khóa mô tả quyền trong Info thì xin quyền sẽ làm app bị đóng, nên ẩn nút micro.
    static var hasUsageDescriptions: Bool {
        ["NSSpeechRecognitionUsageDescription", "NSMicrophoneUsageDescription"].allSatisfy {
            Bundle.main.object(forInfoDictionaryKey: $0) != nil
        }
    }

    var isSupported: Bool { Self.hasUsageDescriptions && recognizer != nil }

    func start() async {
        guard state != .listening else { return }
        guard isSupported, let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }
        guard await authorize() else {
            state = .denied
            return
        }
        do {
            try begin(recognizer)
        } catch {
            cancel()
            state = .unavailable
        }
    }

    /// Dừng thu âm, nhưng vẫn nhận nốt phần chữ còn lại.
    func stop() {
        guard state == .listening else { return }
        silenceTimer?.cancel()
        stopAudio()
        request?.endAudio()
        state = .idle
    }

    /// Dừng hẳn và bỏ phần chưa nhận.
    func cancel() {
        session += 1
        silenceTimer?.cancel()
        stopAudio()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if state == .listening { state = .idle }
    }

    // MARK: - Quyền

    private func authorize() async -> Bool {
        guard await Self.requestSpeechAuthorization() == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Hệ thống gọi lại trên luồng nền, nên closure không được thừa hưởng @MainActor.
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Thu âm

    private func begin(_ recognizer: SFSpeechRecognizer) throws {
        session += 1
        let id = session
        task?.cancel()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Giữ giọng nói trên máy khi máy hỗ trợ tiếng Việt ngoại tuyến.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        try Self.installTap(on: engine.inputNode, request: request)
        engine.prepare()
        try engine.start()

        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.receive(text: text, isFinal: isFinal, failed: failed, session: id) }
        }
        state = .listening
        armSilenceTimer(Self.waitForSpeech)
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func armSilenceTimer(_ duration: Duration) {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func receive(text: String?, isFinal: Bool, failed: Bool, session id: Int) {
        guard id == session else { return }
        if let text, text != transcript {
            transcript = text
            if state == .listening { armSilenceTimer(Self.silenceAfterSpeech) }
        }
        if isFinal || failed {
            silenceTimer?.cancel()
            stopAudio()
            request = nil
            task = nil
            if state == .listening { state = .idle }
        }
    }

    // MARK: - Hai hàm dưới chạy trên luồng âm thanh và luồng nhận dạng.
    // Phải đặt ngoài actor: closure tạo trong hàm của @MainActor sẽ bị gắn @MainActor và crash khi hệ thống gọi từ luồng khác.

    private final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }

    private struct NoInputError: Error {}

    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) throws {
        let format = input.outputFormat(forBus: 0)
        // Máy không có micro (máy ảo, Mac) trả về định dạng rỗng; installTap với định dạng đó làm app crash.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NoInputError() }
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
    }

    nonisolated private static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}
