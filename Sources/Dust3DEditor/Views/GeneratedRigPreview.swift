#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DKit
    import Dust3DRendering
    import SwiftUI

    /// Read-only actual rest data; document assignment actions remain in the template browser.
    struct GeneratedRigPreview: View {
        let store: EditorStore
        let request: GeneratedRigPreviewRequest
        let selectedBoneName: String?
        let isWorkspace: Bool
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(GeneratedRigPreviewSession.self) private var shared: GeneratedRigPreviewSession?
        @State private var fallback: GeneratedRigPreviewSession

        init(
            store: EditorStore, request: GeneratedRigPreviewRequest, selectedBoneName: String? = nil,
            isWorkspace: Bool = false
        ) {
            self.store = store
            self.request = request
            self.selectedBoneName = selectedBoneName
            self.isWorkspace = isWorkspace
            _fallback = State(
                initialValue: GeneratedRigPreviewSession(readSnapshot: { [weak store] in store?.snapshot }))
        }
        private var session: GeneratedRigPreviewSession { shared ?? fallback }
        private var generation: GeneratedRigPreviewState { session.generation }
        private var display: GeneratedRigDisplayState { session.display }
        private struct UpdateKey: Hashable {
            let request: GeneratedRigPreviewRequest
            let selectedName: Data?
            let appearance: RigTemplatePreviewAppearance
        }

        var body: some View {
            let current = store.snapshot.map { request.matchesVersion($0) } ?? false
            let rig = current && session.request == request ? session.currentRig : nil
            let revision = rig == nil ? nil : session.currentRevision
            let selected = rig == nil ? nil : session.selectedIndex
            let name = rig == nil ? "" : session.selectedName
            let displayRequest = rig == nil ? nil : session.desiredDisplay
            let appearance = RigTemplatePreviewPalette.resolve(colorScheme: colorScheme, contrast: contrast)
            let presentationRevision = session.presentationRevision
            let generationRevision = generation.revision
            let displayRevision = display.revision
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Generated rest preview").font(.caption.weight(.semibold))
                    Spacer()
                    if !isWorkspace, shared != nil {
                        Button("Expand") { session.setPresentation(.generatedRest) }
                            .accessibilityLabel("Show generated rest preview in workspace")
                    }
                    cameraMenu(
                        revision: revision,
                        enabled: session.canMoveCamera && rig != nil)
                }
                HStack {
                    Toggle("Model", isOn: Binding(get: { session.showsModel }, set: { session.showsModel = $0 }))
                    Toggle("Bones", isOn: Binding(get: { session.showsBones }, set: { session.showsBones = $0 }))
                    Toggle(
                        "Weights", isOn: Binding(get: { session.showsWeights }, set: { session.setShowsWeights($0) }))
                }
                .toggleStyle(.checkbox)
                if current, generation.request == request, let error = generation.error {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Retry Generation") {
                        session.retryGeneration(request: request, revision: generationRevision)
                    }
                } else if let rig, let revision {
                    jointPicker(rig: rig, revision: revision, selected: selected)
                    if !session.showsModel && !session.showsBones {
                        Text("Model and bones hidden").font(.caption).foregroundStyle(.secondary)
                    } else if !session.showsModel, display.acceptedRequest == displayRequest,
                        session.display.skeletonVertexCount == 0
                    {
                        Text("No drawable bones; joints remain listed below.").font(.caption).foregroundStyle(
                            .secondary)
                    }
                    hierarchySection(rig: rig, revision: revision, selected: selected)
                    ZStack {
                        // Keep the view mounted while display colors change, preserving its camera.
                        if let mesh = display.mesh, display.meshRigRevision == revision {
                            let renderRevision = display.revision
                            MeshViewport(
                                mesh: mesh, isWireframe: session.isWireframe, cameraReset: 0,
                                meshRevision: display.meshRevision, blendsVertexAlpha: true,
                                drawRange: session.drawRange,
                                cameraState: session.cameraState,
                                cameraInteractionAllowed: { [weak session] in
                                    session?.allowsCameraInteraction(
                                        revision: revision, presentationRevision: presentationRevision)
                                        == true
                                },
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
                                Button("Retry Preview") {
                                    session.retryDisplay(request: displayRequest, revision: displayRevision)
                                }
                            }
                        } else if display.acceptedRequest != displayRequest || display.isLoading {
                            ProgressView("Preparing rest preview…").controlSize(.small)
                        }
                    }
                    .frame(
                        minHeight: isWorkspace ? 260 : 160, idealHeight: isWorkspace ? 400 : 180,
                        maxHeight: isWorkspace ? .infinity : 220)
                    Text(
                        "\(rig.joints.count) generated joints. \(rig.eyelidsGenerated ? "Eyelids included." : "No generated eyelids.")"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(name.isEmpty ? "No joint selected" : "Selected joint: \(name)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(
                        session.showsWeights
                            ? "Weight colors: gray means no selected influence; blue to red means increasing selected weight."
                            : "Weight colors hidden; joint selection and numerical properties are preserved."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if display.acceptedRequest == displayRequest, !display.isLoading, display.error == nil,
                        let summary = display.weightSummary
                    {
                        weightSummary(summary)
                    }
                    if let selected {
                        jointProperties(rig: rig, index: selected)
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
            .task(
                id: UpdateKey(
                    request: request, selectedName: selectedBoneName.map { Data($0.utf8) }, appearance: appearance)
            ) {
                guard !Task.isCancelled else { return }
                session.update(request: request, selectedBoneName: selectedBoneName, appearance: appearance)
                if shared == nil, let selectedBoneName {
                    session.setTemplateSelection(selectedBoneName, request: request)
                }
            }
            .onDisappear { if shared == nil { fallback.stop() } }
        }

        private func jointPicker(rig: GeneratedRig, revision: UUID, selected: Int?) -> some View {
            Picker(
                "Weight highlight",
                selection: Binding<Int?>(
                    get: { selected },
                    set: { index in
                        selectJoint(index, rig: rig, revision: revision)
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

        private func selectJoint(_ index: Int?, rig: GeneratedRig, revision: UUID) {
            session.selectJoint(index, revision: revision)
        }

        @ViewBuilder
        private func hierarchySection(rig: GeneratedRig, revision: UUID, selected: Int?) -> some View {
            if let hierarchy = generation.hierarchy {
                DisclosureGroup("Generated joint hierarchy") {
                    OutlineGroup(hierarchy.roots, children: \.children) { node in
                        if rig.joints.indices.contains(node.index) {
                            let joint = rig.joints[node.index]
                            Button {
                                selectJoint(node.index, rig: rig, revision: revision)
                            } label: {
                                HStack {
                                    Text(joint.name)
                                    Spacer()
                                    if joint.head == joint.tail {
                                        Text("Unplaced").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if selected == node.index {
                                        Image(systemName: "checkmark").accessibilityHidden(true)
                                    }
                                }
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(joint.head == joint.tail ? "\(joint.name), unplaced joint" : joint.name)
                            .accessibilityAddTraits(selected == node.index ? .isSelected : [])
                        }
                    }
                }
                .id(revision)
            } else if let error = generation.hierarchyError {
                Text("Joint hierarchy unavailable: \(error)")
                    .font(.caption).textSelection(.enabled)
            }
        }

        private func jointProperties(rig: GeneratedRig, index: Int) -> some View {
            let joint = rig.joints[index]
            return VStack(alignment: .leading, spacing: 2) {
                Text("Selected joint properties").font(.caption.weight(.semibold))
                if let parent = joint.parentIndex {
                    if rig.joints.indices.contains(parent) {
                        Text("Parent: \(rig.joints[parent].name)")
                    } else {
                        Text("Parent unavailable")
                    }
                } else {
                    Text("Root joint")
                }
                Text("Head: \(joint.head.x), \(joint.head.y), \(joint.head.z)")
                Text("Tail: \(joint.tail.x), \(joint.tail.y), \(joint.tail.z)")
                Text("Length: \(joint.lengthInModelUnits, format: .number.precision(.significantDigits(1...6)))")
                Text("Capsule radius: \(joint.capsuleRadius, format: .number.precision(.significantDigits(1...6)))")
                Text(
                    "Closing angle: \(joint.closingAngleDegrees, format: .number.precision(.fractionLength(1))) degrees"
                )
                Text("Coordinates, length and radius use model units.")
            }
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }

        private func weightSummary(_ summary: GeneratedRigWeightSummary) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "Selected weight range: \(summary.minimumWeight, format: .percent) to \(summary.maximumWeight, format: .percent)"
                )
                Text("Influences \(summary.influencedTriangleCount) of \(summary.triangleCount) body triangles")
            }
            .font(.caption).foregroundStyle(.secondary)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
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

        private func fit(revision: UUID?) { session.fit(revision: revision) }
        private func move(_ action: MeshCameraCommand.Action, revision: UUID?) {
            session.move(action, revision: revision)
        }
    }
#endif
