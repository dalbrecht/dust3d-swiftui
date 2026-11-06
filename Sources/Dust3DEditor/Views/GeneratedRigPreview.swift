#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DKit
    import Dust3DRendering
    import SwiftUI

    /// Read-only actual rest data; document assignment actions remain in the template browser.
    struct GeneratedRigPreview: View {
        let store: EditorStore
        let request: GeneratedRigPreviewRequest
        let selectedBoneName: String
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var generation = GeneratedRigPreviewState()
        @State private var display = GeneratedRigDisplayState()
        @State private var selection: GeneratedRigJointSelection?
        @State private var generationRetry = UUID()
        @State private var displayRetry = UUID()
        @State private var cameraReset = 0
        @State private var cameraCommand: MeshCameraCommand?

        private struct GenerationKey: Hashable {
            let request: GeneratedRigPreviewRequest
            let retry: UUID
        }
        private struct DisplayKey: Hashable {
            let request: GeneratedRigDisplayRequest?
            let retry: UUID
        }

        var body: some View {
            let current = store.snapshot.map { request.matches($0) } ?? false
            let rig = current && generation.request == request ? generation.rig : nil
            let revision = rig == nil ? nil : generation.revision
            let selected = rig.flatMap { rig in
                revision.flatMap { revision in
                    selection?.resolvedIndex(in: rig, revision: revision, incomingName: selectedBoneName)
                        ?? (selection?.revision == revision
                            ? nil
                            : rig.joints.firstIndex {
                                $0.name.utf8.elementsEqual(selectedBoneName.utf8)
                            })
                }
            }
            let name = selected.flatMap { rig?.joints[$0].name } ?? ""
            let displayRequest = revision.map {
                GeneratedRigDisplayRequest(
                    rigRevision: $0, selectedBoneName: name,
                    appearance: RigTemplatePreviewPalette.resolve(colorScheme: colorScheme, contrast: contrast))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Generated rest preview").font(.caption.weight(.semibold))
                    Spacer()
                    cameraMenu(
                        revision: revision,
                        enabled: display.acceptedRequest == displayRequest && !display.isLoading && display.error == nil
                            && rig != nil)
                }
                if current, generation.request == request, let error = generation.error {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Retry Generation") { generationRetry = UUID() }
                } else if let rig, let revision {
                    jointPicker(rig: rig, revision: revision, selected: selected)
                    ZStack {
                        // Keep the view mounted while display colors change, preserving its camera.
                        if let mesh = display.mesh, display.meshRigRevision == revision {
                            let renderRevision = display.revision
                            MeshViewport(
                                mesh: mesh, isWireframe: false, cameraReset: cameraReset,
                                meshRevision: display.meshRevision, cameraCommand: cameraCommand,
                                blendsVertexAlpha: true,
                                onError: { cause in
                                    guard let renderRevision, let snapshot = store.snapshot,
                                        request.matches(snapshot), generation.request == request,
                                        generation.revision == revision, display.acceptedRequest == displayRequest
                                    else { return }
                                    display.recordRenderFailure(cause, revision: renderRevision)
                                }
                            )
                            .id(revision)
                            .opacity(
                                display.acceptedRequest == displayRequest && !display.isLoading && display.error == nil
                                    ? 1 : 0
                            )
                            .allowsHitTesting(
                                display.acceptedRequest == displayRequest && !display.isLoading && display.error == nil
                            )
                            .accessibilityHidden(true)
                        }
                        if let error = display.error, display.request == displayRequest {
                            VStack(alignment: .leading) {
                                Text(error).font(.caption).textSelection(.enabled)
                                Button("Retry Preview") { displayRetry = UUID() }
                            }
                        } else if display.acceptedRequest != displayRequest || display.isLoading {
                            ProgressView("Preparing rest preview…").controlSize(.small)
                        }
                    }
                    .frame(minHeight: 160, idealHeight: 180, maxHeight: 220)
                    Text(
                        "\(rig.joints.count) generated joints. \(rig.eyelidsGenerated ? "Eyelids included." : "No generated eyelids.")"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(name.isEmpty ? "No weight highlight" : "Weight highlight: \(name)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(
                        "Weight colors: gray means no selected influence; blue to red means increasing selected weight."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if let selected {
                        let joint = rig.joints[selected]
                        Text(
                            "Joint head: \(joint.head.x), \(joint.head.y), \(joint.head.z). Tail: \(joint.tail.x), \(joint.tail.y), \(joint.tail.z)."
                        )
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !rig.mesh.warning.isEmpty {
                        Text(rig.mesh.warning).font(.caption).textSelection(.enabled)
                    }
                } else if current, generation.request == request, !generation.isLoading {
                    Text("No generated rest geometry").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView("Generating rest preview…").controlSize(.small)
                }
                Text("Rest preview only. Changing the view or weight highlight does not edit the document.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Generated rest preview")
            .task(id: GenerationKey(request: request, retry: generationRetry)) {
                guard !Task.isCancelled, let snapshot = store.snapshot, request.matches(snapshot) else { return }
                cameraCommand = nil
                cameraReset = 0
                await generation.load(request)
            }
            .task(id: DisplayKey(request: displayRequest, retry: displayRetry)) {
                guard !Task.isCancelled else { return }
                guard let displayRequest, let rig, let snapshot = store.snapshot,
                    request.matches(snapshot), generation.request == request,
                    generation.revision == displayRequest.rigRevision
                else { return }
                await display.load(displayRequest, rig: rig)
            }
            .onChange(of: Data(selectedBoneName.utf8)) { _, _ in selection = nil }
            .onDisappear {
                generation.stop()
                display.stop()
            }
        }

        private func jointPicker(rig: GeneratedRig, revision: UUID, selected: Int?) -> some View {
            Picker(
                "Weight highlight",
                selection: Binding<Int?>(
                    get: { selected },
                    set: { index in
                        guard let snapshot = store.snapshot, request.matches(snapshot),
                            generation.request == request, generation.revision == revision,
                            index.map({ rig.joints.indices.contains($0) }) ?? true
                        else { return }
                        selection = GeneratedRigJointSelection(revision: revision, index: index)
                    })
            ) {
                Text("No Weight Highlight").tag(nil as Int?)
                ForEach(rig.joints.indices, id: \.self) { index in
                    let joint = rig.joints[index]
                    Text(joint.head == joint.tail ? "\(joint.name) (Unplaced)" : joint.name).tag(Optional(index))
                }
            }
            .accessibilityLabel("Generated joint weight highlight")
        }

        private func cameraMenu(revision: UUID?, enabled: Bool) -> some View {
            HStack {
                Menu("View") {
                    Button("Rotate Left") { move(.orbitLeft, revision: revision) }
                    Button("Rotate Right") { move(.orbitRight, revision: revision) }
                    Button("Rotate Up") { move(.orbitUp, revision: revision) }
                    Button("Rotate Down") { move(.orbitDown, revision: revision) }
                    Divider()
                    Button("Pan Left") { move(.panLeft, revision: revision) }
                    Button("Pan Right") { move(.panRight, revision: revision) }
                    Button("Pan Up") { move(.panUp, revision: revision) }
                    Button("Pan Down") { move(.panDown, revision: revision) }
                    Divider()
                    Button("Zoom In") { move(.zoomIn, revision: revision) }
                    Button("Zoom Out") { move(.zoomOut, revision: revision) }
                    Button("Fit Model") { fit(revision: revision) }
                }
                .accessibilityLabel("Generated rest preview view controls")
                Button("Fit") { fit(revision: revision) }.accessibilityLabel("Fit generated rest preview")
            }
            .controlSize(.small)
            .disabled(!enabled)
        }

        private func canInteract(revision: UUID?) -> Bool {
            guard let revision, let snapshot = store.snapshot, request.matches(snapshot) else { return false }
            return generation.isCurrent(request: request, revision: revision)
        }

        private func fit(revision: UUID?) {
            guard canInteract(revision: revision) else { return }
            cameraReset += 1
        }

        private func move(_ action: MeshCameraCommand.Action, revision: UUID?) {
            guard canInteract(revision: revision) else { return }
            cameraCommand = MeshCameraCommand(action)
        }
    }
#endif
