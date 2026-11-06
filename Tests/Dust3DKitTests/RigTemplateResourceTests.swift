import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

final class RigTemplateResourceTests: XCTestCase {
    func testAllSevenPinnedTemplatesHaveVerifiedBytesAndMatchingDocumentNames() throws {
        for type in DocumentRigType.allCases where type != .disabled {
            let data = try XCTUnwrap(RigTemplateResources.data(forSourceType: type.rawValue))
            let xml = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
            XCTAssertEqual(xml.rootElement()?.name, "rig")
            XCTAssertEqual(xml.rootElement()?.attribute(forName: "type")?.stringValue, type.rawValue)
            XCTAssertFalse(xml.rootElement()?.elements(forName: "bone").isEmpty ?? true)
            XCTAssertLessThanOrEqual(data.count, RigTemplateResources.maximumBytes)
        }
    }

    func testAbsentAndExplicitNoneDoNotReadAResourceAndUnknownTypesFail() throws {
        var reads = 0
        let read: (String) throws -> Data = { _ in
            reads += 1
            return Data()
        }
        for type in [nil, "", "None"] as [String?] {
            XCTAssertNil(try RigTemplateResources.data(forSourceType: type, read: read))
        }
        XCTAssertThrowsError(try RigTemplateResources.data(forSourceType: "Dragon", read: read)) {
            XCTAssertEqual($0 as? RigTemplateResourceError, .unsupportedType("Dragon"))
        }
        XCTAssertEqual(reads, 0)
    }

    func testDamagedAndOversizedResourceBytesAreRejectedBeforeUse() throws {
        var changed = try XCTUnwrap(RigTemplateResources.data(forSourceType: "Biped"))
        changed[0] ^= 1
        XCTAssertThrowsError(try RigTemplateResources.data(forSourceType: "Biped", read: { _ in changed })) {
            XCTAssertEqual($0 as? RigTemplateResourceError, .invalidResource("Biped"))
            XCTAssertTrue($0.localizedDescription.contains("Biped"))
        }
        for bytes in [Data(), Data("<rig type=\"Biped\"/>".utf8), Data(repeating: 0, count: 16385)] {
            XCTAssertThrowsError(try RigTemplateResources.data(forSourceType: "Biped", read: { _ in bytes })) {
                XCTAssertEqual($0 as? RigTemplateResourceError, .invalidResource("Biped"))
            }
        }
    }

    func testInstalledAppAndExtensionCannotUseFallbackAndResolveTheirOwnCopiedBundle() throws {
        for suffix in ["app", "appex"] {
            try withInstalledApp(bundleExtension: suffix) { app, bundle in
                XCTAssertThrowsError(try RigTemplateResources.resourceBundle(in: bundle)) {
                    XCTAssertEqual($0 as? RigTemplateResourceError, .missingBundle)
                }
                let resources = app.appendingPathComponent("Contents/Resources")
                try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
                let source = try RigTemplateResources.resourceBundle(in: Bundle(for: Self.self))
                let destination = resources.appendingPathComponent("Dust3DNative_Dust3DKit.bundle")
                try FileManager.default.copyItem(at: source.bundleURL, to: destination)
                let installed = try RigTemplateResources.resourceBundle(in: bundle)
                XCTAssertEqual(installed.bundleURL.standardizedFileURL, destination.standardizedFileURL)
                let bytes = try RigTemplateResources.readResource("rig_fish", in: installed)
                XCTAssertEqual(bytes, try RigTemplateResources.data(forSourceType: "Fish"))
            }
        }
    }

    func testFilesystemReadIsBoundedAndMissingFilesHaveExplicitErrors() throws {
        try withInstalledApp { app, _ in
            let resources = app.appendingPathComponent("Contents/Resources/Dust3DNative_Dust3DKit.bundle")
            let templates = resources.appendingPathComponent("RigTemplates")
            try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 20000).write(to: templates.appendingPathComponent("rig_biped.xml"))
            let bundle = try XCTUnwrap(Bundle(url: resources))
            XCTAssertEqual(try RigTemplateResources.readResource("rig_biped", in: bundle).count, 16385)
            XCTAssertThrowsError(try RigTemplateResources.readResource("rig_fish", in: bundle)) {
                XCTAssertEqual($0 as? RigTemplateResourceError, .missingResource("rig_fish"))
            }
        }
    }

    private func withInstalledApp(bundleExtension: String = "app", _ run: (URL, Bundle) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Installed." + bundleExtension)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = ["CFBundleIdentifier": "org.dust3d.resource-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try run(app, XCTUnwrap(Bundle(url: app)))
    }

    func testMissingResourcePreservesTypedFailure() {
        XCTAssertThrowsError(
            try RigTemplateResources.data(
                forSourceType: "Fish",
                read: { name in
                    throw RigTemplateResourceError.missingResource(name)
                })
        ) {
            XCTAssertEqual($0 as? RigTemplateResourceError, .missingResource("rig_fish"))
        }
    }
}
