// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dust3DNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Dust3DEngine", type: .static, targets: ["Dust3DEngine"]),
        .library(name: "Dust3DKit", targets: ["Dust3DKit"]),
        .executable(name: "Dust3DViewer", targets: ["Dust3DViewer"]),
    ],
    targets: [
        .target(
            name: "TriangleIntersection",
            path: "third_party/GuigueDevillers03",
            sources: ["tri_tri_intersect.c"],
            publicHeadersPath: "."
        ),
        .target(
            name: "AutoRemesher",
            path: "third_party/autoremesher",
            exclude: ["LICENSE", "README.md", "thirdparty/isotropicremesher/LICENSE"],
            sources: ["src/AutoRemesher", "thirdparty/isotropicremesher"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("tbbshim"), .headerSearchPath("include"),
                .headerSearchPath("thirdparty/isotropicremesher"), .headerSearchPath("../eigen"),
            ]
        ),
        .target(
            name: "Dust3DCore",
            dependencies: ["AutoRemesher", "TriangleIntersection"],
            path: "dust3d",
            sources: ["base", "mesh", "rig", "uv"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../third_party/autoremesher/tbbshim"),
                .headerSearchPath(".."), .headerSearchPath("../third_party"),
                .headerSearchPath("../third_party/eigen"),
                .headerSearchPath("../third_party/rapidxml-1.13"),
                .headerSearchPath("../third_party/earcut.hpp/include"),
            ]
        ),
        .target(
            name: "Dust3DEngine",
            dependencies: ["Dust3DCore"],
            path: "native/Engine",
            sources: ["Dust3DBridge.cc", "DocumentReader.cc", "SnapshotValidator.cc"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../.."),
                .headerSearchPath("../../third_party/rapidxml-1.13"),
            ]
        ),
        .target(name: "Dust3DKit", dependencies: ["Dust3DEngine"]),
        .executableTarget(
            name: "Dust3DViewer",
            dependencies: ["Dust3DKit"],
            resources: [.copy("Rendering/Shaders.metal")]
        ),
        .testTarget(
            name: "Dust3DKitTests",
            dependencies: ["Dust3DKit", "Dust3DEngine"],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
