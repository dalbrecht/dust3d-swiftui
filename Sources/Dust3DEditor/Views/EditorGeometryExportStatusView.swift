import Accessibility
import Dust3DKit
import Foundation
import SwiftUI

struct EditorGeometryExportStatusView: View {
    let phase: EditorGeometryExportPhase
    var format: DocumentExportFormat = .obj
    let onCancel: () -> Void
    let onDismiss: () -> Void
    let onReveal: (URL) -> Void
    var onAnnouncement: @MainActor (String) -> Void = { announcement in
        AccessibilityNotification.Announcement(announcement).post()
    }

    var body: some View {
        content.onChange(of: phase.accessibilityAnnouncement) { _, announcement in
            if let announcement {
                onAnnouncement(announcement.message)
            }
        }
    }

    var statusAnnouncement: String? { phase.accessibilityAnnouncement?.message }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle, .failed: EmptyView()
        case .choosing: status { activity("Choose an export destination…") }
        case .encoding: status { activity("Exporting \(format.exportName)…") }
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
                        Button(action: { onReveal(receipt.destination) }) {
                            Text("Show in Finder").frame(minHeight: 40)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint("Selects the exported file in Finder")
                        Button(action: onDismiss) { Text("Dismiss").frame(minHeight: 40) }
                            .buttonStyle(.borderless).accessibilityLabel(
                                "Dismiss \(receipt.format.fileExtension.uppercased()) export result")
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
                    "Cancel \(format.fileExtension.uppercased()) export")
        }
    }

    private func status<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content().font(.caption).padding(.horizontal, 12).padding(.vertical, 4)
            Divider()
        }
    }
}
