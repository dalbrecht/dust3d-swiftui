/// Independent Swift-owned mip chains for the established source-baked map roles.
/// Missing chains retain the existing base-only representation; the render boundary
/// validates exact base correspondence and producer caps before GPU allocation.
public struct SourceBakedMipmaps: Sendable {
    public let color: TextureMipChain?
    public let normal: TextureMipChain?
    public let metallic: TextureMipChain?
    public let roughness: TextureMipChain?
    public let emissive: TextureMipChain?

    /// Retain validated owned chains without copying their pixel payload again.
    /// - Parameters:
    ///   - color: Optional sRGB color chain, including its matching base.
    ///   - normal: Optional linear tangent-normal chain.
    ///   - metallic: Optional linear metallic chain.
    ///   - roughness: Optional linear roughness chain.
    ///   - emissive: Optional sRGB emission chain.
    /// - Example: `let maps = SourceBakedMipmaps(color: colorChain)`.
    public init(
        color: TextureMipChain? = nil, normal: TextureMipChain? = nil, metallic: TextureMipChain? = nil,
        roughness: TextureMipChain? = nil, emissive: TextureMipChain? = nil
    ) {
        self.color = color
        self.normal = normal
        self.metallic = metallic
        self.roughness = roughness
        self.emissive = emissive
    }
}
