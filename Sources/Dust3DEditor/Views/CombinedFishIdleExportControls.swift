#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import SwiftUI

    struct CombinedFishIdleExportControls: View {
        let store: EditorStore
        let fileIdentity: UUID
        let destinations: EditorGeometryExportDestinationService
        let documentSourceURL: URL?
        @State private var operation: Task<Void, Never>?
        @State private var receipt: CombinedAnimationPublication.Receipt?
        @State private var errorMessage: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Export Animated FBX and WAVs…", action: begin)
                        .disabled(
                            operation != nil || !store.canManageAnimations || store.authoringCatalog.catalog == nil)
                    if operation != nil {
                        ProgressView().controlSize(.small).accessibilityLabel("Exporting animation")
                        Button("Cancel Export") { operation?.cancel() }
                    }
                }
                Text(
                    "Experimental. Supports clips on their matching template rigs and bakes procedural materials."
                )
                .font(.caption).foregroundStyle(.secondary)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).textSelection(.enabled)
                }
                if let receipt {
                    Text("Saved \(receipt.published.count) files. Silent WAVs skipped: \(receipt.silent.count).")
                        .font(.caption)
                    if let failure = receipt.failure {
                        Label(
                            "\(failure.destination.lastPathComponent): \(failure.cause.localizedDescription)",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption).textSelection(.enabled)
                    }
                    if !receipt.published.isEmpty {
                        DisclosureGroup("Saved Files") {
                            ForEach(receipt.published, id: \.self) { url in
                                Text(verbatim: url.lastPathComponent).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .onChange(of: store.snapshot?.documentRevision) { _, _ in operation?.cancel() }
            .onDisappear { operation?.cancel() }
        }

        private func begin() {
            guard operation == nil else { return }
            receipt = nil
            errorMessage = nil
            do {
                let target = try store.combinedFishIdleExportTarget(fileIdentity: fileIdentity)
                let sourceURL = destinations.attachedDocument?.fileURL ?? documentSourceURL
                operation = Task {
                    defer { operation = nil }
                    do {
                        guard let destination = try await destinations.chooseCombinedFishIdleDestination() else {
                            return
                        }
                        try Task.checkCancellation()
                        let plan = try target.plan(modelName: destination.deletingPathExtension().lastPathComponent)
                        let result = await CombinedAnimationPublication.saveNativeFishIdle(
                            plan: plan, sources: target.sources, modelDestination: destination, sourceURL: sourceURL,
                            isCurrent: {
                                (destinations.attachedDocument?.fileURL ?? documentSourceURL) == sourceURL
                                    && store.isCurrentCombinedFishIdleExport(target)
                            },
                            limits: .init(
                                nativeBytes: 256 * 1024 * 1024, swiftBytes: 64 * 1024 * 1024,
                                combinedBytes: 256 * 1024 * 1024))
                        receipt = result
                        if destinations.hasActiveDocumentWindow {
                            AccessibilityNotification.Announcement(
                                result.failure == nil ? "Animation export complete." : "Animation export stopped."
                            ).post()
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage =
                    "This export requires an accepted document with a supported rig containing clips for its rig."
            }
        }
    }
#endif
