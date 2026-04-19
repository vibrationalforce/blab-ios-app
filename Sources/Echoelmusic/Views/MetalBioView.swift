#if canImport(Metal) && canImport(MetalKit) && canImport(UIKit)
import SwiftUI
import MetalKit

/// SwiftUI wrapper for an MTKView driven by BioVisualRenderer.
struct MetalBioView: UIViewRepresentable {

    let renderer: BioVisualRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = renderer
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#endif
