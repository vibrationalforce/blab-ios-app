import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Single chokepoint deciding whether the on-device LLM features may run.
///
/// The privacy rule lives here, in one place: Echoel's promise is that
/// biometrics stay on the device, so the bio→music "director" is only ever
/// allowed to run against Apple's **on-device** system model. When that model is
/// unavailable, every AI feature turns OFF — it must never silently fall back to
/// Private Cloud Compute or any third-party provider. Callers that want a working
/// experience on iOS 18 (or when the model is absent) use the deterministic,
/// no-LLM `BioDirectionFallback` instead.
public enum OnDeviceModelGate {

    /// True only when Apple's on-device system language model is present and ready.
    /// False on iOS < 26, on devices without the model, and whenever the framework
    /// is unavailable at build time.
    public static var isOnDeviceLLMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        }
        #endif
        return false
    }
}
