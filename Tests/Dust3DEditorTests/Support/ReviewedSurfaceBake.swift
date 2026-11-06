import CryptoKit
import Dust3DKit
import Foundation
import XCTest

/// A test-only admission boundary: no unreviewed generated archive reaches a material native entry point.
actor ReviewedSurfaceBake: ArchiveTextureBaking {
    enum Failure: Error { case unreviewedInput }
    static let expected: [String: (String, Int)] = [
        "cloth-action-full": ("192e596e333eb91c436c88da931b00deb5fae373440ebc498456aeb0ff22ff77", 730),
        "cloth-action-half": ("68cdf8e31389cd7a157f31a90c21d58d60855d3d5386bb61d125b81909488d77", 764),
        "cloth-action-size": ("48395676422a048848e62eda5ca1ee0c480d8dce5f86e65725cd4b5229bf8c93", 766),
        "cloth-start": ("f903aa81e67b5d0a11c99586f8edb288b5df0d9c694a1d7e5de5aac392aae585", 684),
        "skin-Mottled": ("c1ffad1785ddfb7ad4b8cf5db4edc7c43dd55b52d977257cdc42cee043257061", 752),
        "skin-Patches": ("a3a22e9bd06725007d32366d4e9d6d8c8823f1108438dd68e2441c6435b0cd68", 752),
        "skin-Rosettes": ("660977d5ea406ee21a4eb8c6e42c03b7dfca8b5d9c6048ce1db86924b7e7a77e", 753),
        "skin-Spots": ("68fd8dd3b02c6d29498bd0ca2c43aa266e401e6a030a484a6b1821d8b45a5ecc", 750),
        "skin-Stripes": ("38190f02c6d4d27027c9c3008d630222ff256747937a682ab8c85c678e9a4f16", 752),
        "skin-belly": ("672a2e13a41c927e829b08098f48cd124bd649f0d2fa989083c4f03d6dd1a203", 800),
        "skin-ink-red": ("da61e9c2ad8bc307e9c9c3c2e3ec36587c0acff8cf58d53e9716bdafdc820b2a", 811),
        "skin-none": ("e63d41d741e709f471028be61bb073f9f2776f44470f591d223d81ea38b0ed08", 686),
        "skin-size-large": ("0778d160f328566a255c77e26204fee47c5ea78dc6d6cddd6a84c8993277f1e7", 808),
        "skin-size-small": ("25813ffdd3c26f46ba5005def8025a3a298fec6e3dddf377ec6ee13bc3795251", 808),
    ]
    private let baker = ArchiveTextureBakingService()
    private(set) var received: [String] = []
    nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func inputs() throws -> [String: Data] {
        let inputs = try SurfaceDetailFixtureVariants.inputs()
        guard inputs.count == expected.count else { throw Failure.unreviewedInput }
        for (name, bytes) in inputs {
            guard let (hash, count) = expected[name], bytes.count == count, Self.hash(bytes) == hash else {
                XCTFail("Finish archive is outside the root-reviewed input scope: \(name)")
                throw Failure.unreviewedInput
            }
        }
        return inputs
    }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        let hash = Self.hash(data)
        guard Self.expected.values.contains(where: { $0.0 == hash && $0.1 == data.count }) else {
            XCTFail("Unreviewed archive cannot enter the native finish baker")
            throw Failure.unreviewedInput
        }
        received.append(hash)
        return try await baker.load(data: data, options: options, limits: limits)
    }
}
