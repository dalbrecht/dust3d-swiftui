/// Platform-resolved colors shared by template and actual rest-rig previews.
/// Selection and appearance affect display preparation, never rig generation.
struct RigTemplatePreviewAppearance: Sendable, Hashable {
    let boneColor: SIMD4<Float>
    let selectedBoneColor: SIMD4<Float>
    let ringColor: SIMD4<Float>
}
