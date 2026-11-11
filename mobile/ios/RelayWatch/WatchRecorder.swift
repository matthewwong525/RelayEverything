import AVFoundation

// Records the WAV the iPhone's speech engine reads as it is: 16 kHz, one channel, 16-bit, so the phone converts nothing.

final class WatchRecorder: NSObject, AVAudioRecorderDelegate {
  enum Problem: Error { case notStarted }

  private var recorder: AVAudioRecorder?
  /// Runs on the main thread when a recording stops itself at RecordingRules.longest.
  var onLongest: () -> Void = {}

  /// True once the person allowed the microphone, false once they refused, nil before the first ask.
  static var allowed: Bool? {
    switch AVAudioApplication.shared.recordPermission {
    case .granted: return true
    case .denied: return false
    default: return nil
    }
  }

  static func ask(_ done: @escaping (Bool) -> Void) {
    AVAudioApplication.requestRecordPermission { granted in DispatchQueue.main.async { done(granted) } }
  }

  var isRecording: Bool { recorder != nil }

  func start() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .default)
    try session.setActive(true)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ]
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder.isMeteringEnabled = true
    recorder.delegate = self
    guard recorder.record(forDuration: RecordingRules.longest) else { throw Problem.notStarted }
    self.recorder = recorder
  }

  /// The sound level now, from 0 for quiet to 1 for loud.
  func level() -> Double {
    guard let recorder else { return 0 }
    recorder.updateMeters()
    return max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 50) / 50))
  }

  /// Stops, and gives the recording and its length in milliseconds; nil, with the file deleted, when it is too short.
  func stop() -> (URL, Int)? {
    guard let recorder else { return nil }
    self.recorder = nil
    recorder.stop()
    try? AVAudioSession.sharedInstance().setActive(false)
    let url = recorder.url
    let seconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
    guard RecordingRules.keeps(seconds) else {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return (url, Int(seconds * 1000))
  }

  /// Stops and keeps nothing.
  func cancel() {
    guard let recorder else { return }
    self.recorder = nil
    recorder.stop()
    try? AVAudioSession.sharedInstance().setActive(false)
    try? FileManager.default.removeItem(at: recorder.url)
  }

  func audioRecorderDidFinishRecording(_ finished: AVAudioRecorder, successfully flag: Bool) {
    DispatchQueue.main.async {
      // Only a recording this side did not stop, so the one that reached its longest time.
      if self.recorder === finished { self.onLongest() }
    }
  }
}
