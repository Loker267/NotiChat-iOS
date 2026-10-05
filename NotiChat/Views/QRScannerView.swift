import SwiftUI
import AVFoundation

public struct QRScannerView: UIViewControllerRepresentable {
    public var onScan: (String) -> Void
    public var onDismiss: () -> Void

    public init(onScan: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.onScan = onScan
        self.onDismiss = onDismiss
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    public func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    public class Coordinator: NSObject, QRScannerDelegate {
        let parent: QRScannerView

        init(parent: QRScannerView) {
            self.parent = parent
        }

        public func didFindCode(_ code: String) {
            parent.onScan(code)
        }

        public func didCancel() {
            parent.onDismiss()
        }
    }
}

public protocol QRScannerDelegate: AnyObject {
    func didFindCode(_ code: String)
    func didCancel()
}

public class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    public weak var delegate: QRScannerDelegate?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview
        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            captureSession?.stopRunning()
            delegate?.didFindCode(stringValue)
        }
    }
}
