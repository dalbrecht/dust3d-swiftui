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
            url: "https://github.com/dalbrecht/dust3d-core.git", revision: "685b68fb45405dabb4bb6f72c5b0e2598d4b9fdf")
    ],
    targets: [
        .target(name: "Dust3DEditorModel", dependencies: ["Dust3DDocument"], exclude: ["README.md"]),
        .testTarget(name: "Dust3DEditorModelTests", dependencies: ["Dust3DEditorModel", "Dust3DDocument"]),
        .target(
            name: "Dust3DRendering", dependencies: ["Dust3DKit"], exclude: ["README.md"],
            resources: [.copy("Shaders.metal")]),
        .executableTarget(
            name: "Dust3DEditor",
            dependencies: ["Dust3DDocument", "Dust3DEditorModel", "Dust3DKit", "Dust3DRendering"],
            exclude: ["README.md"]),
        .target(name: "Dust3DDocument"),
        .testTarget(name: "Dust3DDocumentTests", dependencies: ["Dust3DDocument"]),
        .target(name: "Dust3DKit", dependencies: [.product(name: "Dust3DEngine", package: "dust3d-core")]),
        .executableTarget(
            name: "Dust3DViewer",
            dependencies: ["Dust3DKit", "Dust3DRendering"]
        ),
        .testTarget(
            name: "Dust3DKitTests",
            dependencies: ["Dust3DKit", "Dust3DDocument", .product(name: "Dust3DEngine", package: "dust3d-core")],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
