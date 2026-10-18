import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class ComponentColorImageSessionTests: XCTestCase {
    private var archive: Data {
        let model = Data(
            "<canvas><nodes/><edges/><parts/><components><component id='c'/><component id='other'/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }
    private var png: Data {
        get throws {
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
                ))
        }
    }
    func testShouldCommitCapturedImageTargetAsOneHistoryStepAndRejectStaleTargets() async throws {
        let session = EditorSession()
        _ = try await session.open(data: archive)
        let selected = try await session.selectComponent("c")
        let target = try XCTUnwrap(ComponentColorImageTarget(snapshot: selected))
        let changed = try await session.importComponentColorImage(png: png, target: target)
        XCTAssertEqual(changed.colorImageAssets.count, 1)
        XCTAssertEqual(changed.selectedComponentID, "c")
        XCTAssertTrue(changed.canUndo)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), archive)
        XCTAssertFalse(undone.canUndo)
        do {
            _ = try await session.importComponentColorImage(png: png, target: target)
            XCTFail("Undo must invalidate a captured source revision")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
        let fresh = try XCTUnwrap(ComponentColorImageTarget(snapshot: undone))
        _ = try await session.selectComponent("other")
        do {
            _ = try await session.importComponentColorImage(png: png, target: fresh)
            XCTFail("Selection changed")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
        _ = try await session.open(data: archive)
        _ = try await session.selectComponent("c")
        do {
            _ = try await session.importComponentColorImage(png: png, target: fresh)
            XCTFail("Document replaced")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
    }
}
