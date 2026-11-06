#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
    import Dust3DKit
    import Dust3DRendering
    import SwiftUI

    /// Local presentation only: selecting or orbiting a template never edits the document.
    struct RigTemplatePreview: View {
        let sourceType: String
        let selectedBoneName: String
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var state = RigTemplatePreviewState()
        @State private var retry = UUID()
        @State private var cameraReset = 0
        @State private var cameraCommand: MeshCameraCommand?

        private struct LoadKey: Hashable {
            let request: RigTemplatePreviewRequest
            let appearance: RigTemplatePreviewAppearance
            let retry: UUID
        }

        var body: some View {
            let request = RigTemplatePreviewRequest(sourceType: sourceType, selectedBoneName: selectedBoneName)
            let key = LoadKey(
                request: request,
                appearance: RigTemplatePreviewPalette.resolve(colorScheme: colorScheme, contrast: contrast),
                retry: retry)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Template preview").font(.caption.weight(.semibold))
                    Spacer()
                    Menu("View") {
                        Button("Rotate Left") { move(.orbitLeft) }
                        Button("Rotate Right") { move(.orbitRight) }
                        Button("Rotate Up") { move(.orbitUp) }
                        Button("Rotate Down") { move(.orbitDown) }
                        Divider()
                        Button("Pan Left") { move(.panLeft) }
                        Button("Pan Right") { move(.panRight) }
                        Button("Pan Up") { move(.panUp) }
                        Button("Pan Down") { move(.panDown) }
                        Divider()
                        Button("Zoom In") { move(.zoomIn) }
                        Button("Zoom Out") { move(.zoomOut) }
                        Button("Fit Template") { cameraReset += 1 }
                    }
                    .accessibilityLabel("Template preview view controls")
                    .disabled(state.request != request || state.displayMesh == nil || state.error != nil)
                    Button("Fit") { cameraReset += 1 }
                        .help("Fit the template in its preview")
                        .accessibilityLabel("Fit template preview")
                        .disabled(state.request != request || state.displayMesh == nil || state.error != nil)
                }
                .controlSize(.small)
                if state.request == request, let error = state.error {
                    Text(error).font(.caption).foregroundStyle(.primary).textSelection(.enabled)
                    Button("Retry Preview") { retry = UUID() }
                } else if state.request == request, let mesh = state.displayMesh, let revision = state.revision {
                    MeshViewport(
                        mesh: mesh, isWireframe: false, cameraReset: cameraReset,
                        cameraCommand: cameraCommand,
                        onError: { state.recordRenderFailure($0, revision: revision) }
                    )
                    .id(revision)
                    .frame(minHeight: 160, idealHeight: 180, maxHeight: 220)
                    // Equivalent camera actions are exposed through the native View menu.
                    .accessibilityHidden(true)
                    Text(
                        selectedBoneName.isEmpty
                            ? "\(state.mesh?.boneNames.count ?? 0) template bones"
                            : "Selected template bone: \(selectedBoneName)"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                } else if state.request == request, !state.isLoading {
                    Text("No template geometry").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading template preview…").controlSize(.small)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Template preview")
            .task(id: key) {
                cameraReset = 0
                cameraCommand = nil
                await state.load(request, appearance: key.appearance)
            }
            .onDisappear { state.stop() }
        }

        private func move(_ action: MeshCameraCommand.Action) { cameraCommand = MeshCameraCommand(action) }

    }
#endif
