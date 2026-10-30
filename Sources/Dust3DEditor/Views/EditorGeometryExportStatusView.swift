import Dust3DKit
import Foundation
import SwiftUI

struct EditorGeometryExportStatusView: View {
    let phase: EditorGeometryExportPhase
    var format: DocumentExportFormat = .obj
    let onCancel: () -> Void
    let onDismiss: () -> Void

    @ViewBuilder var body: some View {
        switch phase {
        case .idle, .failed: EmptyView()
        case .choosing: status { activity("Choose an export destination…") }
        case .encoding: status { activity("Exporting \(format.rawValue.uppercased()) geometry…") }
        case .cancelling: status { activity("Finishing current export…") }
        case .completed(let receipt):
            status {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Label("Exported \(receipt.destination.lastPathComponent)", systemImage: "checkmark.circle")
                            .lineLimit(1).truncationMode(.middle).help(receipt.destination.path)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(receipt.byteCount), countStyle: .file))
                            .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                        Spacer(minLength: 8)
                        Button(action: onDismiss) { Text("Dismiss").frame(minHeight: 40) }
                            .buttonStyle(.borderless).accessibilityLabel(
                                "Dismiss \(receipt.format.rawValue.uppercased()) export result")
                    }
                    if !receipt.warning.isEmpty {
                        Text("Export warning: \(receipt.warning)").textSelection(.enabled)
                            .id(receipt.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func activity(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).accessibilityLabel(title)
            Text(title).accessibilityHidden(true)
            Spacer(minLength: 8)
            Button(action: onCancel) { Text("Cancel").frame(minHeight: 40) }
                .buttonStyle(.borderless).disabled(!phase.canCancel).accessibilityLabel(
                    "Cancel \(format.rawValue.uppercased()) export")
        }
    }

    private func status<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content().font(.caption).padding(.horizontal, 12).padding(.vertical, 4)
            Divider()
        }
    }
}
