import Dust3DDocument
import Dust3DEditorModel
import Foundation

struct CombinedFishIdleExportTarget: Sendable {
    let fileIdentity: UUID
    let sources: [SuppliedAnimationSource]
    private let rig: GeneratedRigPreviewRequest
    private let animations: [DocumentAnimation]
    private let surfaces: [String]

    init(snapshot: EditorSnapshot, fileIdentity: UUID, surfaces: [String]) throws {
        let animations = try snapshot.document.animations()
        let rig = GeneratedRigPreviewRequest(snapshot: snapshot)
        guard (1...128).contains(animations.count), surfaces.count == 8,
            animations.allSatisfy({ FishIdleCopyReceipt.supportsClipType($0.type, rigType: rig.sourceType) })
        else { throw FishIdleCopyError.sourceMismatch }
        self.fileIdentity = fileIdentity
        self.rig = rig
        self.animations = animations
        self.surfaces = surfaces
        let revision = UUID()
        sources = animations.map {
            SuppliedAnimationSource(
                playbackRequest: .init(fileIdentity: fileIdentity, rig: rig, animation: $0, queryID: revision),
                rigRevision: revision)
        }
    }

    func matches(_ snapshot: EditorSnapshot, fileIdentity: UUID) -> Bool {
        self.fileIdentity == fileIdentity && rig.matchesVersion(snapshot)
    }

    func plan(modelName: String) throws -> CombinedAnimationExportPlan {
        try CombinedAnimationExportPlan(modelName: modelName, animations: animations, surfaces: surfaces)
    }
}
