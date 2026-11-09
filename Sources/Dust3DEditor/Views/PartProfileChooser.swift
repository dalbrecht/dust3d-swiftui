import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct PartProfileChooser: View {
    let store: EditorStore
    let part: DocumentPart
    var choose: (@MainActor (CutFaceSelection) -> Void)? = nil
    @State private var query = ""
    @State private var preview: (documentID: UUID, ownerID: [UInt8], profileID: [UInt8])?

    private var candidates: [DocumentPart] {
        PartProfileOptions.candidates(in: store.snapshot?.parts ?? [], excluding: part.id, matching: query)
    }

    var body: some View {
        let snapshot = store.snapshot
        let candidates = self.candidates
        let spokenTitles = PartProfileOptions.spokenTitles(for: candidates)
        let ownerID = Array(part.id.utf8)
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search profile parts", text: $query)
                .accessibilityIdentifier("part-profile-search")
                .focusedValue(\.editorTextEditing, true)
            if candidates.isEmpty {
                Text("No matching other parts.").font(.caption)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates) { candidate in
                            let spokenTitle = spokenTitles[candidate.id] ?? candidate.title
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title).lineLimit(1)
                                    Text(candidate.id).font(.caption2).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Button("Preview") {
                                    guard let snapshot, store.snapshot?.documentIdentity == snapshot.documentIdentity
                                    else { return }
                                    preview = (snapshot.documentIdentity, ownerID, Array(candidate.id.utf8))
                                }
                                .accessibilityLabel("Preview profile \(spokenTitle)")
                                Button("Choose") {
                                    guard let snapshot, let current = store.snapshot,
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
