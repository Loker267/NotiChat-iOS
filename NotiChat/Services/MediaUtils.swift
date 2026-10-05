import UIKit
import AVFoundation

public final class MediaUtils {
    /**
     * Resizes a UIImage to max bounding box of 400px and compresses it as JPEG (quality 0.5).
     * Returns Base64 string matching Android's MediaUtils.compressImageToBase64.
     */
    public static func compressImageToBase64(_ image: UIImage) -> String? {
        let maxDimension: CGFloat = 400.0
        let width = image.size.width
        let height = image.size.height

        var newWidth = width
        var newHeight = height

        if width > height {
            if width > maxDimension {
                newWidth = maxDimension
                newHeight = height * (maxDimension / width)
            }
        } else {
            if height > maxDimension {
                newHeight = maxDimension
                newWidth = width * (maxDimension / height)
            }
        }

        let newSize = CGSize(width: newWidth, height: newHeight)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let finalImage = resizedImage,
              let jpegData = finalImage.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }
}

public final class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public var isRecording = false
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    public func startRecording() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)

            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("temp_voice_note.m4a")
            try? FileManager.default.removeItem(at: fileURL)
            self.recordingURL = fileURL

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 16000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            return true
        } catch {
            print("Failed to start recording: \(error)")
            isRecording = false
            return false
        }
    }

    public func stopRecording() -> String? {
        audioRecorder?.stop()
        isRecording = false

        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path),
              let audioData = try? Data(contentsOf: url) else {
            return nil
        }
        return audioData.base64EncodedString()
    }

    public func cancelRecording() {
        audioRecorder?.stop()
        isRecording = false
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

public final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public var isPlaying = false
    private var audioPlayer: AVAudioPlayer?
    private var onFinishedCallback: (() -> Void)?

    public func playAudioFromBase64(_ base64Audio: String, onFinished: @escaping () -> Void) {
        stopPlaying()
        self.onFinishedCallback = onFinished

        guard let data = Data(base64Encoded: base64Audio.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")) else {
            onFinished()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Failed to play voice message: \(error)")
            isPlaying = false
            onFinished()
        }
    }

    public func stopPlaying() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
        }
        audioPlayer = nil
        isPlaying = false
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        onFinishedCallback?()
    }
}
