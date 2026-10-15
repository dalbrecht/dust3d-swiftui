// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dust3DNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Dust3DKit", targets: ["Dust3DKit"]),
        .library(name: "Dust3DDocument", targets: ["Dust3DDocument"]),
        .executable(name: "Dust3DViewer", targets: ["Dust3DViewer"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/dalbrecht/dust3d-core.git", revision: "685b68fb45405dabb4bb6f72c5b0e2598d4b9fdf")
    ],
    targets: [
        .target(name: "Dust3DDocument"),
        .testTarget(name: "Dust3DDocumentTests", dependencies: ["Dust3DDocument"]),
        .target(name: "Dust3DKit", dependencies: [.product(name: "Dust3DEngine", package: "dust3d-core")]),
        .executableTarget(
            name: "Dust3DViewer",
            dependencies: ["Dust3DKit"],
            resources: [.copy("Rendering/Shaders.metal")]
        ),
        .testTarget(
            name: "Dust3DKitTests",
            dependencies: ["Dust3DKit", "Dust3DDocument", .product(name: "Dust3DEngine", package: "dust3d-core")],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
