#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DKit
    import SwiftUI

    /// Window-owned disclosure survives replacing the inspector or workspace surface.
    struct GeneratedRigHierarchyView: View {
        let session: GeneratedRigPreviewSession
        let rig: GeneratedRig
        let hierarchy: GeneratedRigHierarchy
        let revision: UUID
        let selected: Int?
        let presentationRevision: UUID

        var body: some View {
            let disclosure = session.hierarchyDisclosure
            let reveal = disclosure.reveal
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    Button("Reveal Selected Joint") {
                        session.revealSelectedJoint(revision: revision, presentationRevision: presentationRevision)
                    }
                    .disabled(selected == nil)
                    .help("Expand the selected joint's ancestors and scroll it into view.")
                }
                DisclosureGroup(
                    "Generated joint hierarchy",
                    isExpanded: Binding(
                        get: { disclosure.isExpanded },
                        set: {
                            session.setHierarchyExpanded(
                                $0, index: nil, revision: revision, presentationRevision: presentationRevision)
                        })
                ) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(hierarchy.roots) { node in
                                    GeneratedRigHierarchyRow(
                                        session: session, rig: rig, node: node, revision: revision,
                                        selected: selected, presentationRevision: presentationRevision)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: min(180, max(44, CGFloat(rig.joints.count) * 34)))
                        .task(id: reveal) { @MainActor in
                            guard let reveal else { return }
                            await Task.yield()
                            guard !Task.isCancelled,
                                session.acceptsHierarchyReveal(reveal, presentationRevision: presentationRevision)
                            else { return }
                            proxy.scrollTo(reveal.index, anchor: .center)
                        }
                    }
                }
            }
            .id(revision)
        }
    }

    private struct GeneratedRigHierarchyRow: View {
        let session: GeneratedRigPreviewSession
        let rig: GeneratedRig
        let node: GeneratedRigHierarchy.Node
        let revision: UUID
        let selected: Int?
        let presentationRevision: UUID

        var body: some View {
            Group {
                if let children = node.children {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { session.hierarchyDisclosure.expanded.contains(node.index) },
                            set: {
                                session.setHierarchyExpanded(
                                    $0, index: node.index, revision: revision,
                                    presentationRevision: presentationRevision)
                            })
                    ) {
                        ForEach(children) { child in
                            GeneratedRigHierarchyRow(
                                session: session, rig: rig, node: child, revision: revision,
                                selected: selected, presentationRevision: presentationRevision)
                        }
                    } label: {
                        jointButton
                    }
                } else {
                    jointButton
                }
            }
        }

        @ViewBuilder private var jointButton: some View {
            if rig.joints.indices.contains(node.index) {
                let joint = rig.joints[node.index]
                Button {
                    guard session.presentationRevision == presentationRevision else { return }
                    session.selectJoint(node.index, revision: revision)
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
                .id(node.index)
            }
        }
    }
#endif
