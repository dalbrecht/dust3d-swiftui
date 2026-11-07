import AppKit
import Dust3DDocument
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ComponentPartRoleStoreTests: XCTestCase {
    /// Canonicalize only triangle order and cyclic starting corners; preserve winding and every coincident occurrence.
    private func triangles(_ mesh: IndexedMesh) -> [[UInt32]] {
        stride(from: 0, to: mesh.indices.count, by: 3).map { start in
            let corners = (0..<3).map { offset -> [UInt32] in
                let p = mesh.vertices[Int(mesh.indices[start + offset])].position
                return [p.x.bitPattern, p.y.bitPattern, p.z.bitPattern]
            }
            let rotations = (0..<3).map { offset in (0..<3).flatMap { corners[($0 + offset) % 3] } }
            return rotations.sorted { $0.lexicographicallyPrecedes($1) }[0]
        }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Role edit/preview did not settle")
    }

    // Bounded ordinary profiles from the maintained positive stitching fixture: three 3-node lines or two 4-node loops.
    // No imported assets, catalog APIs, legacy writer, fault injection or quarantined archive is involved.
    @MainActor func testActualSidebarActionBuildsLineAndLoopSurfacesWithExactHistoryAndReopen() async throws {
        for loop in [false, true] {
            let expected = try StitchingFixture.document(loop: loop, attributes: "")
            var source = try expected.applying(.ungroupComponent(id: StitchingFixture.groupID))
            let components = try source.components().filter { $0.partID != nil }.map(\.id)
            source = try source.applying(
                .setComponentPartRoles(componentIDs: components, target: .model, newGroupID: nil))
            let store = EditorStore()
            defer { store.stop() }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            let unavailable = store.componentPartRoleAction(.stitchingLine)
            await store.load(data: source.encoded())
            try await settle(store)
            store.selectComponents(Set(components))
            try await settle(store)
            unavailable()
            XCTAssertFalse(store.isWorking)
            let role: PartTarget = loop ? .stitchingLoop : .stitchingLine
            XCTAssertTrue(store.canAssignComponentPartRole(role))
            let action = store.componentPartRoleAction(role)
            action()
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            let result = try XCTUnwrap(store.snapshot)
            let browse = try XCTUnwrap(store.componentGroupBrowse)
            XCTAssertEqual(browse.children.map(\.id), components)
            XCTAssertEqual(result.selectedComponentIDs, Set(components))
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(result.document.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let mesh = try XCTUnwrap(store.mesh)
            XCTAssertGreaterThan(mesh.triangleCount, 0)
            XCTAssertTrue(
                mesh.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite })
            let independent = try MeshLoader.loadIndexed(data: expected.encoded())
            XCTAssertEqual(mesh.triangleCount, independent.triangleCount)
            XCTAssertEqual(triangles(mesh), triangles(independent))
            let reopened = try Dust3DDocument(data: result.document.encoded())
            let reopenMesh = try MeshLoader.loadIndexed(data: reopened.encoded())
            XCTAssertEqual(triangles(reopenMesh), triangles(mesh))
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            XCTAssertFalse(store.snapshot?.canUndo == true)
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), result.document.encoded())
        }
    }

    @MainActor func testCapturedActionRejectsSelectionAwayBackAndControlsRenderBothAppearances() async throws {
        let source = try StitchingFixture.document(loop: false)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let ids = Set(try source.components().filter { $0.partID != nil }.map(\.id))
        store.selectComponents(ids)
        try await settle(store)
        let action = store.componentPartRoleAction(.cutFace)
        store.clearComponentSelection()
        try await settle(store)
        store.selectComponents(ids)
        try await settle(store)
        action()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        for scheme in [ColorScheme.light, .dark] {
            let png = try InspectorRenderer.png(ComponentPartRoleControls(store: store), width: 270, scheme: scheme)
            XCTAssertGreaterThan(png.count, 100)
            if let directory = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                try png.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent(
                        "component-part-roles-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
    @MainActor func testReusedGroupWithUnselectedSiblingOpensInHostedSidebar() async throws {
        let baseline = try StitchingFixture.document(loop: false)
        let xml = try XMLDocument(data: baseline.modelXML)
        let container = try XCTUnwrap(xml.rootElement()?.elements(forName: "components").first)
        let group = try XCTUnwrap(container.elements(forName: "component").first)
        group.addChild(XMLElement(name: "component", stringValue: nil))
        let extra = try XCTUnwrap(group.elements(forName: "component").last)
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "id"
        attribute.stringValue = "unselected"
        extra.addAttribute(attribute)
        group.detach()
        let prefix = (0..<25).map { "<component id='prefix\($0)'/>" }.joined()
        let temporary = try XMLElement(xmlString: "<component id='outer'>\(group.xmlString)</component>")
        let prefixXML = try XMLElement(xmlString: "<components>\(prefix)</components>")
        for element in prefixXML.elements(forName: "component") {
            element.detach()
            container.addChild(element)
        }
        container.addChild(temporary)
        let source = try Dust3DDocument(snapshotXML: xml.xmlData(options: [.nodePreserveAll]))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let disclosure = ComponentSidebarDisclosure(collapsedIDs: ["outer", StitchingFixture.groupID])
        let host = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 0) {
                ComponentSidebar(store: store, disclosure: disclosure)
            }.frame(width: 300, height: 240))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 300, height: 240), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        window.contentView = host
        host.frame = .init(x: 0, y: 0, width: 300, height: 240)
        store.selectComponents(Set(try source.components().filter { $0.partID != nil }.map(\.id)))
        try await settle(store)
        store.componentPartRoleAction(.stitchingLine)()
        try await settle(store)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let browse = try XCTUnwrap(store.componentGroupBrowse)
        XCTAssertEqual(browse.path.map(\.id), ["outer", StitchingFixture.groupID])
        XCTAssertEqual(browse.children.last?.id, "unselected")
        XCTAssertFalse(store.snapshot?.selectedComponentIDs.contains("unselected") == true)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.snapshot?.canUndo == true)
        XCTAssertEqual(disclosure.collapsedIDs, ["outer", StitchingFixture.groupID])
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { table(in: $0) }.first
        }
        let nativeTable = try XCTUnwrap(table(in: host))
        XCTAssertEqual(nativeTable.numberOfRows, browse.children.count)
        XCTAssertTrue(NSLocationInRange(0, nativeTable.rows(in: nativeTable.visibleRect)))
    }

}
