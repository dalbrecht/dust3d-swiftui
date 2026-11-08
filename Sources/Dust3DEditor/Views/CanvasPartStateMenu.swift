import Dust3DDocument
import SwiftUI

struct CanvasPartStateMenu: View {
    let store: EditorStore?
    let admitsInput: @MainActor () -> Bool

    var body: some View {
        let lock = store?.canvasPartStateAction(.locked)
        let disable = store?.canvasPartStateAction(.disabled)
        Menu("Owning Part State") {
            Button("Lock or Unlock Owning Part") { if admitsInput() { lock?() } }
                .help("Press L while the canvas has keyboard focus.")
            Button("Enable or Disable Owning Part") { if admitsInput() { disable?() } }
                .help("Press J while the canvas has keyboard focus.")
        }
        .disabled(!admitsInput() || lock == nil || disable == nil)
    }
}
