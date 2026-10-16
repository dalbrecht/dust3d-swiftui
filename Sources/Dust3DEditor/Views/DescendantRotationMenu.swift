import Dust3DEditorModel
import SwiftUI

struct DescendantRotationMenu: View {
    let store: EditorStore?

    var body: some View {
        Menu("Rotate Around Selected Node") {
            ForEach(DescendantRotation.allCases, id: \.self) { rotation in
                Button(rotation.rawValue) { store?.rotateDescendants(rotation) }
            }
        }
        .disabled(store?.canRotateDescendants != true)
        .help(
            "Select one editable pivot and set a document origin. The pivot stays fixed; connected nodes rotate away from the neighbor nearest the origin. Axis and part locks apply."
        )
    }
}
