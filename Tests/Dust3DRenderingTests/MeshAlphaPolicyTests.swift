import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

final class MeshAlphaPolicyTests: XCTestCase {
    func testOpaquePolicyDisablesBlendingAndKeepsOpaqueShaderOutput() {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        attachment.isBlendingEnabled = true
        MeshAlphaPolicy.opaque.configure(attachment)
        XCTAssertFalse(attachment.isBlendingEnabled)
        XCTAssertEqual(MeshAlphaPolicy.opaque.shaderOption, 0)
    }

    func testVertexAlphaUsesQtSourceAlphaBlendFactors() {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        MeshAlphaPolicy.vertexAlpha.configure(attachment)
        XCTAssertTrue(attachment.isBlendingEnabled)
        XCTAssertEqual(attachment.rgbBlendOperation, .add)
        XCTAssertEqual(attachment.alphaBlendOperation, .add)
        XCTAssertEqual(attachment.sourceRGBBlendFactor, .sourceAlpha)
        XCTAssertEqual(attachment.destinationRGBBlendFactor, .oneMinusSourceAlpha)
        XCTAssertEqual(attachment.sourceAlphaBlendFactor, .sourceAlpha)
        XCTAssertEqual(attachment.destinationAlphaBlendFactor, .oneMinusSourceAlpha)
        XCTAssertEqual(MeshAlphaPolicy.vertexAlpha.shaderOption, 1)
    }

    func testPolicyEpochRejectsQueuedErrorsAcrossAnABATransition() {
        var request = MeshAlphaRequestState()
        XCTAssertTrue(request.update(blendsVertexAlpha: false))
        let firstOpaque = request.epoch
        XCTAssertTrue(request.accepts(firstOpaque))
        XCTAssertFalse(request.update(blendsVertexAlpha: false))
        XCTAssertEqual(request.epoch, firstOpaque)
        XCTAssertTrue(request.update(blendsVertexAlpha: true))
        let blended = request.epoch
        XCTAssertFalse(request.accepts(firstOpaque))
        XCTAssertTrue(request.accepts(blended))
        XCTAssertTrue(request.update(blendsVertexAlpha: false))
        XCTAssertFalse(request.accepts(firstOpaque))
        XCTAssertFalse(request.accepts(blended))
        XCTAssertTrue(request.accepts(request.epoch))
    }

    @MainActor
    func testExpandedViewportRequiresExplicitAlphaOptIn() {
        let mesh = Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: "")
        let opaque = MeshViewport(mesh: mesh, isWireframe: false, cameraReset: 0, onError: { _ in })
        let blended = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 0, blendsVertexAlpha: true, onError: { _ in })
        XCTAssertFalse(opaque.blendsVertexAlpha)
        XCTAssertTrue(blended.blendsVertexAlpha)
    }
}
