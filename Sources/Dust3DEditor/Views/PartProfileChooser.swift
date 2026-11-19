import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct PartProfileChooser: View {
    let store: EditorStore
    let part: DocumentPart
    var choose: (@MainActor (CutFaceSelection) -> Void)? = nil
    @State private var query = ""
    @State private var preview: (documentID: UUID, ownerID: [UInt8], profileID: [UInt8])?

    var body: some View {
        let snapshot = store.snapshot
        let candidates =
            snapshot.map { PartProfileOptions.candidates(in: $0, excluding: part.id, matching: query) }
            ?? []
        let spokenTitles = PartProfileOptions.spokenTitles(for: candidates)
        let cyclicProfiles =
            snapshot.map { CutFaceLinks.cyclicChoices(from: part.id, parts: $0.parts, nodes: $0.nodes) }
            ?? []
        let ownerID = Array(part.id.utf8)
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search profile parts", text: $query)
                .accessibilityIdentifier("part-profile-search")
                .focusedValue(\.editorTextEditing, true)
            if candidates.isEmpty {
                Text(query.isEmpty ? "Set a part’s role to Cut Face to add a profile." : "No matching profiles.")
                    .font(.caption)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates) { candidate in
                            let spokenTitle = spokenTitles[candidate.id] ?? candidate.title
                            let wouldCycle =
                                cyclicProfiles.contains(candidate.id)
                                && part.cutFace != .linkedPart(candidate.id)
                            let label = VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title).fixedSize(horizontal: false, vertical: true)
                                if spokenTitle != candidate.title {
                                    Text(candidate.id).font(.caption2).monospaced()
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if wouldCycle {
                                    Text("Would create a profile cycle").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            let actions = HStack(spacing: 8) {
                                Button("Preview") {
                                    guard let snapshot, store.snapshot?.documentIdentity == snapshot.documentIdentity
                                    else { return }
                                    preview = (snapshot.documentIdentity, ownerID, Array(candidate.id.utf8))
                                }
                                .accessibilityLabel("Preview profile \(spokenTitle)")
                                Button("Choose") {
                                    guard !wouldCycle, let snapshot, let current = store.snapshot,
                                        current.documentIdentity == snapshot.documentIdentity,
                                        current.documentRevision == snapshot.documentRevision
                                    else { return }
                                    if let choose {
                                        choose(.linkedPart(candidate.id))
                                    } else {
                                        store.setPartCutFace(part.id, selection: .linkedPart(candidate.id))
                                    }
                                }
                                .accessibilityLabel("Link profile \(spokenTitle)")
                                .disabled(wouldCycle)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                label
                                actions.frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .help(candidate.title + "\n" + candidate.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .accessibilityLabel("Profile parts")
            }
            if let snapshot, let preview, preview.documentID == snapshot.documentIdentity, preview.ownerID == ownerID,
                let profile = snapshot.parts.first(where: { $0.id.utf8.elementsEqual(preview.profileID) })
            {
                LinkedCutFacePreviewView(snapshot: snapshot, partID: profile.id, title: profile.title)
            }
            Text("Preview shows the authored Front outline. Choose links the profile. Cyclic links are rejected.")
                .font(.caption).foregroundStyle(.primary)
        }
        .onChange(of: ownerID) { _, _ in
            query = ""
            preview = nil
        }
        .onChange(of: snapshot?.documentIdentity) { _, _ in
            query = ""
            preview = nil
        }
    }
}
