import Foundation
import Vision
import AVFoundation
import Combine

/// Manages hand tracking using Vision framework
/// Provides 21-point skeleton detection per hand at 30 Hz
@MainActor
class HandTrackingManager: ObservableObject {

    // MARK: - Published Properties

    /// Left hand detected
    @Published var leftHandDetected: Bool = false

    /// Right hand detected
    @Published var rightHandDetected: Bool = false

    /// Left hand landmarks (21 points)
    @Published var leftHandLandmarks: [HandLandmark] = []

    /// Right hand landmarks (21 points)
    @Published var rightHandLandmarks: [HandLandmark] = []

    /// Left hand position in 3D space (normalized -1 to 1)
    @Published var leftHandPosition: SIMD3<Float> = .zero

    /// Right hand position in 3D space (normalized -1 to 1)
    @Published var rightHandPosition: SIMD3<Float> = .zero

    /// Tracking confidence (0.0 - 1.0)
    @Published var trackingConfidence: Float = 0.0


    // MARK: - Hand Landmark Model

    struct HandLandmark: Identifiable {
        let id = UUID()
        let jointName: VNHumanHandPoseObservation.JointName
        let position: CGPoint // Normalized 0-1
        let confidence: Float
    }

    // Joint names for reference
    static let allJointNames: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]


    // MARK: - Private Properties

    private var handPoseRequest: VNDetectHumanHandPoseRequest?
    private var isTracking: Bool = false
    private var sequenceHandler = VNSequenceRequestHandler()


    // MARK: - Initialization

    init() {
        setupHandPoseRequest()
        print("👋 HandTrackingManager initialized")
    }


    // MARK: - Setup

    private func setupHandPoseRequest() {
        handPoseRequest = VNDetectHumanHandPoseRequest { [weak self] request, error in
            Task { @MainActor in
                self?.handleHandPoseRequest(request: request, error: error)
            }
        }

        handPoseRequest?.maximumHandCount = 2 // Track both hands
        handPoseRequest?.revision = VNDetectHumanHandPoseRequestRevision1
    }


    // MARK: - Tracking Control

    /// Start hand tracking
    func startTracking() {
        guard !isTracking else { return }

        isTracking = true
        print("👋 Started hand tracking")
    }

    /// Stop hand tracking
    func stopTracking() {
        guard isTracking else { return }

        isTracking = false
        leftHandDetected = false
        rightHandDetected = false
        leftHandLandmarks.removeAll()
        rightHandLandmarks.removeAll()
        trackingConfidence = 0.0

        print("👋 Stopped hand tracking")
    }

    /// Process video frame for hand detection
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isTracking, let request = handPoseRequest else { return }

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            print("❌ Hand tracking error: \(error)")
        }
    }


    // MARK: - Request Handling

    private func handleHandPoseRequest(request: VNRequest, error: Error?) {
        if let error = error {
            print("❌ Hand pose request error: \(error)")
            return
        }

        guard let observations = request.results as? [VNHumanHandPoseObservation] else {
            // No hands detected
            leftHandDetected = false
            rightHandDetected = false
            leftHandLandmarks.removeAll()
            rightHandLandmarks.removeAll()
            trackingConfidence = 0.0
            return
        }

        // Process detected hands
        processHandObservations(observations)
    }

    private func processHandObservations(_ observations: [VNHumanHandPoseObservation]) {
        // Reset detection flags
        leftHandDetected = false
        rightHandDetected = false
        leftHandLandmarks.removeAll()
        rightHandLandmarks.removeAll()

        var totalConfidence: Float = 0.0

        for observation in observations {
            // Determine if left or right hand based on position
            // (Left hand typically on left side of frame)
            let wristPoint = try? observation.recognizedPoint(.wrist)
            let isLeftHand = (wristPoint?.location.x ?? 0.5) < 0.5

            // Extract all landmarks
            var landmarks: [HandLandmark] = []

            for jointName in Self.allJointNames {
                if let point = try? observation.recognizedPoint(jointName),
                   point.confidence > 0.3 {
                    let landmark = HandLandmark(
                        jointName: jointName,
                        position: point.location,
                        confidence: point.confidence
                    )
                    landmarks.append(landmark)
                    totalConfidence += point.confidence
                }
            }

            // Calculate 3D position (using wrist as reference)
            let position = calculate3DPosition(from: landmarks)

            if isLeftHand {
                leftHandDetected = true
                leftHandLandmarks = landmarks
                leftHandPosition = position
            } else {
                rightHandDetected = true
                rightHandLandmarks = landmarks
                rightHandPosition = position
            }
        }

        // Update overall tracking confidence
        let landmarkCount = leftHandLandmarks.count + rightHandLandmarks.count
        trackingConfidence = landmarkCount > 0 ? totalConfidence / Float(landmarkCount) : 0.0
    }

    /// Calculate 3D position from hand landmarks
    /// Returns normalized position (-1 to 1 for x,y and 0 to 1 for z/depth)
    private func calculate3DPosition(from landmarks: [HandLandmark]) -> SIMD3<Float> {
        guard let wrist = landmarks.first(where: { $0.jointName == .wrist }) else {
            return .zero
        }

        // X: Horizontal position (normalized -1 to 1)
        let x = Float(wrist.position.x) * 2.0 - 1.0

        // Y: Vertical position (normalized -1 to 1)
        let y = Float(wrist.position.y) * 2.0 - 1.0

        // Z: Depth estimation based on hand size
        // (Larger hand span = closer to camera)
        let handSpan = calculateHandSpan(landmarks)
        let z = min(handSpan * 2.0, 1.0) // Normalize to 0-1

        return SIMD3<Float>(x, y, z)
    }

    /// Calculate hand span (distance from wrist to middle finger tip)
    private func calculateHandSpan(_ landmarks: [HandLandmark]) -> Float {
        guard let wrist = landmarks.first(where: { $0.jointName == .wrist }),
              let middleTip = landmarks.first(where: { $0.jointName == .middleTip }) else {
            return 0.0
        }

        let dx = Float(middleTip.position.x - wrist.position.x)
        let dy = Float(middleTip.position.y - wrist.position.y)

        return sqrt(dx * dx + dy * dy)
    }


    // MARK: - Helper Methods

    /// Get specific joint position for a hand
    func getJointPosition(hand: Hand, joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
        let landmarks = hand == .left ? leftHandLandmarks : rightHandLandmarks
        return landmarks.first(where: { $0.jointName == joint })?.position
    }

    /// Get distance between two joints
    func getJointDistance(hand: Hand, from: VNHumanHandPoseObservation.JointName, to: VNHumanHandPoseObservation.JointName) -> Float? {
        guard let fromPos = getJointPosition(hand: hand, joint: from),
              let toPos = getJointPosition(hand: hand, joint: to) else {
            return nil
        }

        let dx = Float(toPos.x - fromPos.x)
        let dy = Float(toPos.y - fromPos.y)

        return sqrt(dx * dx + dy * dy)
    }

    /// Get finger extension (0 = closed, 1 = extended)
    func getFingerExtension(hand: Hand, finger: Finger) -> Float {
        let landmarks = hand == .left ? leftHandLandmarks : rightHandLandmarks

        guard let wrist = landmarks.first(where: { $0.jointName == .wrist }),
              let tip = landmarks.first(where: { $0.jointName == finger.tipJoint }) else {
            return 0.0
        }

        // Calculate distance from wrist to finger tip
        let dx = Float(tip.position.x - wrist.position.x)
        let dy = Float(tip.position.y - wrist.position.y)
        let distance = sqrt(dx * dx + dy * dy)

        // Normalize (typical extended finger is ~0.3 in normalized space)
        return min(distance / 0.3, 1.0)
    }

    /// Check if finger is curled (closed)
    func isFingerCurled(hand: Hand, finger: Finger) -> Bool {
        return getFingerExtension(hand: hand, finger: finger) < 0.4
    }

    enum Hand {
        case left, right
    }

    enum Finger {
        case thumb, index, middle, ring, little

        var tipJoint: VNHumanHandPoseObservation.JointName {
            switch self {
            case .thumb: return .thumbTip
            case .index: return .indexTip
            case .middle: return .middleTip
            case .ring: return .ringTip
            case .little: return .littleTip
            }
        }
    }
}


// MARK: - Camera Integration Helper

extension HandTrackingManager {
    /// Create camera capture session for hand tracking
    func createCaptureSession() -> AVCaptureSession? {
        let session = AVCaptureSession()
        session.sessionPreset = .vga640x480 // 30 Hz for hand tracking

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ Failed to create camera input")
            return nil
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(nil, queue: DispatchQueue(label: "handTracking"))

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        return session
    }
}
