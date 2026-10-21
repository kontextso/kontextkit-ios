/// The creative type for Open Measurement (OM) SDK sessions.
///
/// Decoded from the `/preload` response and consumed by
/// `OMManager.createSession(...)` to choose between an `htmlDisplay` and a
/// `video` OMID configuration. Not exposed on publisher-facing bid APIs
/// (parity with sdk-js, which omits this field).
public enum OMCreativeType: String, Sendable, Hashable, Decodable {
    /// A static or rich-media display ad.
    case display
    /// A video ad creative.
    case video
}
