import Dust3DEditorModel
import SwiftUI

struct LinkedCutFacePreviewView: View {
    let snapshot: EditorSnapshot
    let partID: String
    let title: String

    private struct Request: Hashable {
        let documentID: UUID
        let revision: Int
        let partID: [UInt8]
    }

    @State private var result: (request: Request, contour: [CanvasPoint]?)?

    var body: some View {
        let request = Request(
            documentID: snapshot.documentIdentity, revision: snapshot.documentRevision,
            partID: Array(partID.utf8))
        VStack(alignment: .leading, spacing: 4) {
            Text("Authored Front outline: \(title)").font(.caption)
            if let result, result.request == request {
                if let contour = result.contour {
                    Canvas { context, size in
                        let scale = min(size.width, size.height) * 0.35
                        let points = contour.map {
                            CGPoint(x: size.width / 2 + $0.x * scale, y: size.height / 2 - $0.y * scale)
                        }
                        var path = Path()
                        path.addLines(points)
                        path.closeSubpath()
                        context.fill(path, with: .color(.primary.opacity(0.1)), style: FillStyle(eoFill: true))
                        context.stroke(path, with: .foreground, lineWidth: 1.5)
                    }
                    .frame(height: 80)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Authored Front outline of \(title)")
                    .accessibilityAddTraits(.isImage)
                } else {
                    Text("Preview unavailable for this profile.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("Loading profile outline")
            }
        }
        .task(id: request) {
            let contour = LinkedCutFacePreview.contour(partID: partID, snapshot: snapshot)
            guard !Task.isCancelled else { return }
            result = (request, contour)
        }
    }
}
