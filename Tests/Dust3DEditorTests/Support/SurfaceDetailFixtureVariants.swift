import Dust3DDocument
import Foundation

/// Pure archive construction for root source/hash review; this helper never calls the native engine.
enum SurfaceDetailFixtureVariants {
    static let groupID = WrappingFixture.groupID
    static func inputs() throws -> [String: Data] {
        let skin = try WrappingFixture.document(mode: "Skin")
        var result = ["skin-none": skin.encoded()]
        for pattern in ComponentSurfacePattern.allCases where pattern != .none {
            result["skin-" + pattern.rawValue] = try skin.applying(
                .setComponentSurfacePattern(id: groupID, pattern: pattern)
            ).encoded()
        }
        let spots = try skin.applying(.setComponentSurfacePattern(id: groupID, pattern: .spots))
        result["skin-ink-red"] = try spots.applying(
            .setComponentSurfaceColor(id: groupID, color: .init(red: 200, green: 20, blue: 30))
        ).encoded()
        result["skin-size-small"] = try spots.applying(
            .setComponentSurfaceScalar(id: groupID, property: .patternScale, value: 0.03)
        ).encoded()
        result["skin-size-large"] = try spots.applying(
            .setComponentSurfaceScalar(id: groupID, property: .patternScale, value: 0.12)
        ).encoded()
        result["skin-belly"] = try spots.applying(.setComponentSurfaceScalar(id: groupID, property: .belly, value: 1))
            .encoded()
        let cloth = try Dust3DDocument(data: SurfaceDetailPositiveFixture.cloth(wrinkles: false))
        result["cloth-start"] = cloth.encoded()
        let full = try cloth.applying(.setComponentSurfaceScalar(id: groupID, property: .wrinkles, value: 1))
        result["cloth-action-full"] = full.encoded()
        result["cloth-action-half"] = try full.applying(
            .setComponentSurfaceScalar(id: groupID, property: .wrinkles, value: 0.5)
        ).encoded()
        result["cloth-action-size"] = try full.applying(
            .setComponentSurfaceScalar(id: groupID, property: .wrinkleSize, value: 2)
        ).encoded()
        return result
    }
}
