import Foundation
import Observation

/// Manages scene presets and smooth transitions for live performance.
/// A scene is a named snapshot of voice mix + tonal character.
/// Launching a scene morphs SoundscapeEngine parameters over ~2 seconds.
@MainActor @Observable
final class ClipEngine {

    // MARK: - Scene model

    struct Scene: Identifiable {
        var id: UUID = UUID()
        var name: String
        var mixRoot:   Float        // 0…0.6
        var mixFifth:  Float
        var mixOctave: Float
        var mixHigh:   Float
        var harmonicity: Float      // 0=noisy, 1=pure
        var color: SceneColor

        enum SceneColor: CaseIterable {
            case teal, amber, rose, violet, sky, lime
        }
    }

    // MARK: - State

    private(set) var scenes: [Scene] = ClipEngine.defaultScenes
    private(set) var activeSceneID: UUID?
    private(set) var queuedSceneID: UUID?       // next beat pending
    private(set) var isMorphing: Bool = false

    // MARK: - Morphing

    private var morphTimer: Timer?
    private var morphStep: Int = 0
    private let morphSteps: Int = 40            // 40 × 50ms = 2s
    private var morphTarget: Scene?
    private var morphOrigin: (root: Float, fifth: Float, octave: Float, high: Float)?

    // MARK: - Engine reference

    private weak var soundscapeEngine: SoundscapeEngine?

    func connect(to engine: SoundscapeEngine) {
        self.soundscapeEngine = engine
    }

    // MARK: - Launch

    /// Immediately launch a scene (or queue for next beat if engine is playing).
    func launch(_ scene: Scene) {
        guard let eng = soundscapeEngine else { return }

        queuedSceneID = scene.id

        if eng.isPlaying {
            // Quantize to ~1-beat (250ms at 120 BPM) — simple delay
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.applyScene(scene)
            }
        } else {
            applyScene(scene)
        }
    }

    /// Launch all scenes with index `sceneIndex` across tracks (full scene row).
    func launchScene(at index: Int) {
        guard index < scenes.count else { return }
        launch(scenes[index])
    }

    // MARK: - Capture

    /// Save current engine state as a new scene.
    func captureCurrentState(name: String = "Scene \(UUID().uuidString.prefix(4))") {
        guard let eng = soundscapeEngine else { return }
        let colors = Scene.SceneColor.allCases
        let color = colors[scenes.count % colors.count]
        let scene = Scene(
            name: name,
            mixRoot:     eng.mixRoot,
            mixFifth:    eng.mixFifth,
            mixOctave:   eng.mixOctave,
            mixHigh:     eng.mixHigh,
            harmonicity: Float(eng.voiceRoot.harmonicity),
            color: color
        )
        scenes.append(scene)
    }

    /// Rename a scene by ID.
    func rename(_ scene: Scene, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        scenes[i].name = trimmed
    }

    /// Remove a scene by ID.
    func remove(_ scene: Scene) {
        scenes.removeAll { $0.id == scene.id }
        if activeSceneID == scene.id { activeSceneID = nil }
    }

    // MARK: - Private morphing

    private func applyScene(_ scene: Scene) {
        guard let eng = soundscapeEngine else { return }
        morphTimer?.invalidate()
        morphOrigin = (eng.mixRoot, eng.mixFifth, eng.mixOctave, eng.mixHigh)
        morphTarget = scene
        morphStep   = 0
        isMorphing  = true
        activeSceneID = scene.id
        queuedSceneID = nil

        // Apply harmonicity immediately (no interpolation needed — DDSP handles smoothly)
        for voice in eng.allVoices {
            voice.harmonicity = Double(scene.harmonicity)
        }

        morphTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceMorph() }
        }

        log.log(.info, category: .audio, "Scene launched: \(scene.name)")
    }

    private func advanceMorph() {
        guard let eng = soundscapeEngine,
              let origin = morphOrigin,
              let target = morphTarget else {
            morphTimer?.invalidate()
            isMorphing = false
            return
        }

        morphStep += 1
        let t = Float(morphStep) / Float(morphSteps)
        let smooth = t * t * (3 - 2 * t)   // smoothstep

        eng.mixRoot   = origin.root   + (target.mixRoot   - origin.root)   * smooth
        eng.mixFifth  = origin.fifth  + (target.mixFifth  - origin.fifth)  * smooth
        eng.mixOctave = origin.octave + (target.mixOctave - origin.octave) * smooth
        eng.mixHigh   = origin.high   + (target.mixHigh   - origin.high)   * smooth

        if morphStep >= morphSteps {
            morphTimer?.invalidate()
            morphTimer  = nil
            isMorphing  = false
            morphTarget = nil
            morphOrigin = nil
        }
    }

    // MARK: - Defaults

    static let defaultScenes: [Scene] = [
        Scene(name: "Rise",    mixRoot: 0.40, mixFifth: 0.15, mixOctave: 0.08, mixHigh: 0.04, harmonicity: 0.95, color: .teal),
        Scene(name: "Float",   mixRoot: 0.25, mixFifth: 0.25, mixOctave: 0.20, mixHigh: 0.10, harmonicity: 0.85, color: .sky),
        Scene(name: "Shimmer", mixRoot: 0.10, mixFifth: 0.15, mixOctave: 0.30, mixHigh: 0.35, harmonicity: 0.75, color: .violet),
        Scene(name: "Dream",   mixRoot: 0.35, mixFifth: 0.20, mixOctave: 0.12, mixHigh: 0.08, harmonicity: 0.60, color: .amber),
        Scene(name: "Dark",    mixRoot: 0.55, mixFifth: 0.10, mixOctave: 0.05, mixHigh: 0.02, harmonicity: 0.40, color: .rose),
        Scene(name: "Pulse",   mixRoot: 0.30, mixFifth: 0.30, mixOctave: 0.15, mixHigh: 0.05, harmonicity: 0.98, color: .lime),
    ]
}
