// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dust3DNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Dust3DKit", targets: ["Dust3DKit"]),
        .library(name: "Dust3DDocument", targets: ["Dust3DDocument"]),
        .library(name: "Dust3DEditorModel", targets: ["Dust3DEditorModel"]),
        .executable(name: "Dust3DViewer", targets: ["Dust3DViewer"]),
        .executable(name: "Dust3DEditor", targets: ["Dust3DEditor"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/dalbrecht/dust3d-core.git", revision: "2703a17ce4c1f8d21a30b23580b45520ef49c87b")
    ],
    targets: [
        .target(name: "Dust3DEditorModel", dependencies: ["Dust3DDocument"], exclude: ["README.md"]),
        .testTarget(name: "Dust3DEditorModelTests", dependencies: ["Dust3DEditorModel", "Dust3DDocument"]),
        .target(
            name: "Dust3DRendering", dependencies: ["Dust3DKit"], exclude: ["README.md"],
            resources: [.copy("Shaders.metal")]),
        .testTarget(
            name: "Dust3DRenderingTests", dependencies: ["Dust3DRendering", "Dust3DKit", "Dust3DDocument"]),
        .executableTarget(
            name: "Dust3DEditor",
            dependencies: ["Dust3DDocument", "Dust3DEditorModel", "Dust3DKit", "Dust3DRendering"],
            exclude: ["README.md"]),
        .testTarget(name: "Dust3DEditorTests", dependencies: ["Dust3DEditor", "Dust3DDocument"]),
        .target(name: "Dust3DDocument", exclude: ["README.md"]),
        .testTarget(name: "Dust3DDocumentTests", dependencies: ["Dust3DDocument"]),
        .target(
            name: "Dust3DKit",
            dependencies: ["Dust3DDocument", .product(name: "Dust3DEngine", package: "dust3d-core")]),
        .executableTarget(
            name: "Dust3DViewer",
            dependencies: ["Dust3DKit", "Dust3DRendering"], exclude: ["README.md"]
        ),
        .testTarget(name: "Dust3DViewerTests", dependencies: ["Dust3DViewer", "Dust3DKit"]),
        .testTarget(
            name: "Dust3DKitTests",
            dependencies: [
                "Dust3DKit", "Dust3DDocument", "Dust3DEditorModel",
                .product(name: "Dust3DEngine", package: "dust3d-core"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
