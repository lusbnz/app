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
        stopAudio()
        request?.endAudio()
        state = .idle
    }

    /// Dừng hẳn và bỏ phần chưa nhận.
    func cancel() {
        stopAudio()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if state == .listening { state = .idle }
    }

    // MARK: - Quyền

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Thu âm

    private func begin(_ recognizer: SFSpeechRecognizer) throws {
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

        Self.installTap(on: engine.inputNode, request: request)
        engine.prepare()
        try engine.start()

        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.receive(text: text, isFinal: isFinal, failed: failed) }
        }
        state = .listening
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func receive(text: String?, isFinal: Bool, failed: Bool) {
        if let text { transcript = text }
        if isFinal || failed {
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

    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
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
