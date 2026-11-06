#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
    import Dust3DKit
    import Foundation
    import Observation

    /// Byte identity avoids Swift String canonical-equivalence coalescing distinct bones.
    struct RigTemplatePreviewRequest: Sendable, Hashable {
        let sourceType: String?
        let selectedBoneName: String

        init(sourceType: String?, selectedBoneName: String = "") {
            self.sourceType = sourceType
            self.selectedBoneName = selectedBoneName
        }

        static func == (left: Self, right: Self) -> Bool {
            left.sourceType.map { Data($0.utf8) } == right.sourceType.map { Data($0.utf8) }
                && left.selectedBoneName.utf8.elementsEqual(right.selectedBoneName.utf8)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(sourceType.map { Data($0.utf8) })
            hasher.combine(Data(selectedBoneName.utf8))
        }
    }

    struct RigTemplatePreviewAppearance: Sendable, Hashable {
        let boneColor: SIMD4<Float>
        let selectedBoneColor: SIMD4<Float>
        let ringColor: SIMD4<Float>
    }

    private struct RigTemplatePreviewPrepared: Sendable {
        let mesh: RigTemplateMesh?
        let displayMesh: Mesh?
    }

    /// One surface owns its worker and publication epoch; document state is untouched.
    @MainActor @Observable
    final class RigTemplatePreviewState {
        private(set) var request: RigTemplatePreviewRequest?
        private(set) var revision: UUID?
        private(set) var mesh: RigTemplateMesh?
        private(set) var displayMesh: Mesh?
        private(set) var error: String?
        private(set) var isLoading = false
        @ObservationIgnored private var worker: Task<RigTemplatePreviewPrepared, Error>?
        @ObservationIgnored private let loader: @Sendable (RigTemplatePreviewRequest) async throws -> RigTemplateMesh?

        init(
            loader: @escaping @Sendable (RigTemplatePreviewRequest) async throws -> RigTemplateMesh? = { request in
                try RigTemplateMesh.load(sourceType: request.sourceType, selectedBoneName: request.selectedBoneName)
            }
        ) {
            self.loader = loader
        }

        func load(_ request: RigTemplatePreviewRequest, appearance: RigTemplatePreviewAppearance? = nil) async {
            worker?.cancel()
            let stamp = UUID()
            revision = stamp
            self.request = request
            mesh = nil
            displayMesh = nil
            error = nil
            isLoading = true
            let loader = loader
            let task = Task.detached(priority: .userInitiated) {
                let mesh = try await loader(request)
                try Task.checkCancellation()
                let display: Mesh?
                if let mesh, let appearance {
                    display = try mesh.displayMesh(
                        boneColor: appearance.boneColor,
                        selectedBoneColor: appearance.selectedBoneColor, ringColor: appearance.ringColor)
                } else {
                    display = nil
                }
                return RigTemplatePreviewPrepared(mesh: mesh, displayMesh: display)
            }
            worker = task
            let result: Result<RigTemplatePreviewPrepared, Error>
            do {
                result = .success(
                    try await withTaskCancellationHandler {
                        try await task.value
                    } onCancel: {
                        task.cancel()
                    })
            } catch {
                result = .failure(error)
            }
            guard revision == stamp else { return }
            worker = nil
            isLoading = false
            guard !Task.isCancelled else {
                revision = nil
                self.request = nil
                return
            }
            switch result {
            case .success(let value):
                mesh = value.mesh
                displayMesh = value.displayMesh
            case .failure(is CancellationError): break
            case .failure(let cause): error = EditorStore.message(cause)
            }
        }

        func recordRenderFailure(_ cause: String, revision: UUID) {
            guard self.revision == revision, mesh != nil, !isLoading else { return }
            error = cause
        }

        func stop() {
            worker?.cancel()
            worker = nil
            revision = nil
            request = nil
            mesh = nil
            displayMesh = nil
            error = nil
            isLoading = false
        }
    }
#endif
