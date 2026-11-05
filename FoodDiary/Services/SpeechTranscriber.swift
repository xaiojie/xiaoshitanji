import AVFoundation
import Observation
import Speech

/// 说一餐：优先用设备端识别，不行才走系统服务；说完把文字交给输入框。
@MainActor
@Observable
final class SpeechTranscriber {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        errorMessage = nil
        guard await Self.requestPermission() else {
            errorMessage = "没有拿到麦克风或语音识别权限，去系统设置里打开就能用。"
            return
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "语音识别暂时不可用，先手动输入吧。"
            return
        }
        stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "麦克风被别的 App 占着，稍后再试。"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 能本地识别就不把声音送出去。
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // 采样率为 0 时 installTap 会抛 Objective-C 异常，直接崩掉，必须先挡一下。
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "麦克风暂时不可用，先手动输入吧。"
            cleanUp()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        input.removeTap(onBus: 0)
        // 音频回调在实时线程上，不能继承 MainActor 隔离；`request` 只是把数据转交给
        // 识别器，跨线程追加是它支持的用法。
        nonisolated(unsafe) let audioRequest = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            audioRequest.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "麦克风启动失败，稍后再试。"
            cleanUp()
            return
        }
        isRecording = true
        transcript = ""

        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if finished { self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording || request != nil else { return }
        cleanUp()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanUp() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }

    /// 系统会在任意队列上回调，不能让它继承 MainActor 隔离，否则 Swift 6 的
    /// 执行器检查会直接 SIGTRAP（crash 日志里是 dispatch_assert_queue_fail）。
    private nonisolated static func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
