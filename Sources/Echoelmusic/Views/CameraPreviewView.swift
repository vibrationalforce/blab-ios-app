#if canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import AVFoundation
import UIKit

/// Wraps AVCaptureVideoPreviewLayer as a SwiftUI view.
/// Used in the Stream tab to show live camera feed while recording.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    // MARK: - UIView subclass that exposes AVCaptureVideoPreviewLayer

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
