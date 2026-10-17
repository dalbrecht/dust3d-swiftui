import AppKit
import Dust3DDocument
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class PartModifierRenderingTests: XCTestCase {
    private let partID = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private func document(unsupported: Bool, cutFace: String? = nil, target: String? = nil) throws -> Dust3DDocument {
        let flags = PartModifierProperty.allCases.map { property in
            let enabled = property == .subdivision || property == .roundedEnds || property == .hardJoin
            return "\(property.rawValue)='\(unsupported ? "future" : enabled ? "true" : "false")'"
        }.joined(separator: " ")
        let cutAttributes =
            "cutFace='\(cutFace ?? (unsupported ? "future" : "Triangle"))' cutRotation='\(unsupported ? "future" : "0.005")'"
        let name = unsupported ? "QA Unsupported Flags" : "QA Known Flags"
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='.5'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(partID)' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='\(partID)' name='\(name)' future='preserved' metallic='\(unsupported ? "future" : "0.5")' roughness='\(unsupported ? "future" : "0.25")' emissive='\(unsupported ? "future" : "2")' target='\(target ?? (unsupported ? "future" : "Model"))' \(cutAttributes) deformWidth='\(unsupported ? "future" : "0.995")' deformThickness='\(unsupported ? "future" : "1.25")' deformUnified='\(unsupported ? "future" : "true")' \(flags)/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(partID)' color='#3366cc'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Inspector fixture did not settle")
    }
    private func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "dust3d-editor-ui-qa-\(UUID().uuidString)", isDirectory: true)
    }
    private func save(_ data: Data, name: String, directory: URL) throws {
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertGreaterThan(image.pixelsWide, 0)
        XCTAssertGreaterThan(image.pixelsHigh, 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".png")
        try data.write(to: url, options: .atomic)
        print("Inspector QA artifact: \(url.path)")
    }
    @MainActor func testActualInspectorRendersKnownAndUnsupportedStatesWithoutEditingDocument() async throws {
        let directory = outputDirectory()
        for unsupported in [false, true] {
            let original = try document(unsupported: unsupported)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            store.selectPart(partID)
            try await settle(store)
            if unsupported {
                XCTAssertNotNil(store.previewState.errorMessage)
            } else {
                XCTAssertNil(store.previewState.errorMessage)
            }
            let part = try XCTUnwrap(store.snapshot?.selectedPart)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    PartInspector(store: store, part: part), width: 250, scheme: scheme)
                try save(
                    data,
                    name:
                        "part-inspector-\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")",
                    directory: directory)
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testModifierSectionRendersWithoutPublishingAnEdit() async throws {
        let original = try document(unsupported: false)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let part = try XCTUnwrap(store.snapshot?.parts.first)
        let data = try InspectorRenderer.png(PartModifierControls(store: store, part: part), width: 250, scheme: .light)
        try save(data, name: "part-modifier-section", directory: outputDirectory())
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
    }
    @MainActor func testDeformationControlsRenderWithoutChangingSourceOrHistory() async throws {
        for unsupported in [false, true] {
            let original = try document(unsupported: unsupported)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            let part = try XCTUnwrap(store.snapshot?.parts.first)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    PartDeformationControls(store: store, part: part), width: 250, scheme: scheme)
                try save(
                    data,
                    name:
                        "part-deformation-\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")",
                    directory: outputDirectory())
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testMaterialControlsRenderKnownAndUnsupportedValuesWithoutEdits() async throws {
        for unsupported in [false, true] {
            let original = try document(unsupported: unsupported, target: "Model")
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            let part = try XCTUnwrap(store.snapshot?.parts.first)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    PartMaterialControls(store: store, part: part), width: 250, scheme: scheme)
                try save(
                    data,
                    name:
                        "part-material-\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")",
                    directory: outputDirectory())
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testCutFaceControlsRenderPresetsUnsupportedAndUnresolvedProfilesWithoutEdits() async throws {
        for unsupported in [false, true] {
            for profile in [nil, "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"] as [String?] {
                let original = try document(unsupported: unsupported, cutFace: profile)
                let store = EditorStore()
                defer { store.stop() }
                await store.load(data: original.encoded())
                try await settle(store)
                let part = try XCTUnwrap(store.snapshot?.parts.first)
                for scheme in [ColorScheme.light, .dark] {
                    let data = try InspectorRenderer.png(
                        PartCutFaceControls(store: store, part: part), width: 250, scheme: scheme)
                    try save(
                        data,
                        name:
                            "part-cut-face-\(profile == nil ? "preset" : "unresolved")-\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")",
                        directory: outputDirectory())
                    XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                    XCTAssertFalse(store.canUndo)
                }
            }
        }
    }
    @MainActor func testProfileChooserAndResolvedLinkRenderWithoutPublishingAnEdit() async throws {
        for hasProfiles in [false, true] {
            var original = try document(unsupported: false)
            if hasProfiles {
                for (index, id) in ["{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"]
                    .enumerated()
                {
                    original = try original.applying(
                        .addNode(
                            id: index == 0
                                ? "{22222222-2222-4222-8222-222222222222}" : "{33333333-3333-4333-8333-333333333333}",
                            partID: id,
                            componentID: index == 0
                                ? "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}" : "{ffffffff-ffff-4fff-8fff-ffffffffffff}",
                            position: .init(x: Double(index + 2), y: 0.5, z: 0.5), radius: 0.1))
                    original = try original.applying(
                        .setPartName(
                            id: id,
                            name: "Long duplicate profile name with Unicode 曲線"))
                }
                original = try original.applying(
                    .setPartCutFace(
                        id: partID,
                        selection: .linkedPart("{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}")))
            }
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            let part = try XCTUnwrap(store.snapshot?.parts.first(where: { $0.id == partID }))
            for scheme in [ColorScheme.light, .dark] {
                let suffix = "\(hasProfiles ? "populated" : "empty")-\(scheme == .dark ? "dark" : "light")"
                try save(
                    InspectorRenderer.png(PartProfileChooser(store: store, part: part), width: 250, scheme: scheme),
                    name: "part-profile-chooser-" + suffix, directory: outputDirectory())
                if hasProfiles {
                    try save(
                        InspectorRenderer.png(
                            PartCutFaceControls(store: store, part: part), width: 250, scheme: scheme),
                        name: "part-profile-resolved-" + suffix, directory: outputDirectory())
                }
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testPartTargetControlsRenderSupportedAndUnsupportedRolesWithoutEditing() async throws {
        for role in PartTarget.allCases.map(\.rawValue) + ["future", "ImportedModel"] {
            let original = try document(unsupported: false, target: role)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            let part = try XCTUnwrap(store.snapshot?.parts.first)
            for scheme in [ColorScheme.light, .dark] {
                try save(
                    InspectorRenderer.png(PartTargetControls(store: store, part: part), width: 250, scheme: scheme),
                    name: "part-target-\(role)-\(scheme == .dark ? "dark" : "light")", directory: outputDirectory())
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testInvalidRenderWidthsRejectBeforeWindowCreation() {
        for width in [CGFloat.zero, -1, .infinity, 1001] {
            XCTAssertThrowsError(try InspectorRenderer.png(Text("No window"), width: width, scheme: .light)) {
                XCTAssertEqual($0 as? InspectorRenderer.Failure, .invalidSize)
            }
        }
    }
}
