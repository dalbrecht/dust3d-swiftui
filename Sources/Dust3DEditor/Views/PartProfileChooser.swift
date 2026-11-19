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
