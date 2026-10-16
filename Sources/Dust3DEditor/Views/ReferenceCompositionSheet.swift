import CoreGraphics
import Dust3DEditorModel
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct ReferenceCompositionSheet: View {
    let store: EditorStore
    let target: ReferenceCompositionTarget
    @Environment(\.dismiss) private var dismiss
    @State private var recoveryIdentity = UUID()
    @State private var draft = ReferenceCompositionDraft()
    @State private var importingProfile = ReferenceProfile.front
    @State private var isImporting = false
    @State private var setsOrigin = true
    @State private var isApplying = false
    @State private var applyError: String?
    @State private var applyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Compose Reference Image").font(.title2)
                    Text(
                        "Crop Front and Side sources into one turnaround image. Changes stay in this sheet until Apply."
                    )
                    .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(ReferenceProfile.allCases, id: \.self) { profile in
                            ReferenceCompositionPanel(profile: profile, draft: draft) {
                                importingProfile = profile
                                isImporting = true
                            }
                        }
                    }
                    HStack {
                        Button("Swap Front and Side") { draft.swapProfiles() }
                            .disabled(draft.front == nil && draft.side == nil)
                        if store.hasReferenceImage {
                            Button("Use Existing Image as Front") {
                                guard let image = store.referenceImageForComposition else { return }
                                draft.useExisting(image)
                            }
                            .disabled(store.referenceImageForComposition == nil)
                            .help(
                                "The stored image is flattened. Its original Front/Side sources and crops cannot be recovered."
                            )
                        }
                    }
                    GroupBox("Composed preview") {
                        if let result = draft.result {
                            Image(decorative: result.image, scale: 1).resizable().scaledToFit()
                                .accessibilityLabel("Composed turnaround image")
                        } else {
                            ContentUnavailableView(
                                draft.isWorking ? "Preparing preview…" : "Import a profile to begin",
                                systemImage: "photo")
                        }
                    }
                    .frame(height: 180)
                    if draft.isWorking { ProgressView("Preparing reference image…").controlSize(.small) }
                    if let error = draft.errorMessage { Label(error, systemImage: "exclamationmark.triangle") }
                    if let applyError { Label(applyError, systemImage: "exclamationmark.triangle") }
                    Toggle("Set document origin to profile centers (axis locks apply)", isOn: $setsOrigin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }
            HStack {
                Text("Apply replaces canvas.png in one undo step.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isApplying)
                Button(isApplying ? "Applying…" : "Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canApply || store.isWorking || isApplying)
            }
        }
        .padding(20)
        .frame(width: 920, height: 760)
        .disabled(isApplying)
        .interactiveDismissDisabled(isApplying)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.png, .jpeg, .bmp, .gif, .tiff]) { result in
            switch result {
            case .success(let url): draft.importSource(url: url, profile: importingProfile)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { draft.reportImportFailure(error) }
            }
        }
        .onAppear {
            EditorCompositionRecovery.shared.register(recoveryIdentity) {
                guard !isApplying else { return false }
                draft.stop()
                dismiss()
                return true
            }
        }
        .onDisappear {
            EditorCompositionRecovery.shared.unregister(recoveryIdentity)
            draft.stop()
            applyTask?.cancel()
        }
    }

    private func apply() {
        guard !isApplying, draft.canApply, let result = draft.result else { return }
        isApplying = true
        applyError = nil
        applyTask = Task {
            let succeeded = await store.applyReferenceComposition(result, target: target, setsOrigin: setsOrigin)
            guard !Task.isCancelled else { return }
            isApplying = false
            if succeeded {
                dismiss()
            } else {
                applyError = store.errorMessage ?? "The editor is unavailable. Reopen the composer."
            }
        }
    }
}

@MainActor private struct ReferenceCompositionPanel: View {
    let profile: ReferenceProfile
    let draft: ReferenceCompositionDraft
    let importImage: () -> Void
    @State private var values = ["", "", "", ""]
    private var source: ReferenceCompositionSource? { draft.source(profile) }

    var body: some View {
        GroupBox(profile.rawValue) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Import \(profile.rawValue)…", action: importImage)
                    Button("Remove") { draft.remove(profile) }.disabled(source == nil)
                    if profile == .side {
                        Button(source?.isMirrored == true ? "Unmirror Side" : "Mirror Side") {
                            draft.toggleSideMirror()
                        }
                        .disabled(source == nil)
                    }
                }
                if let source {
                    ReferenceCropPreview(source: source) { crop in
                        draft.setPointerCrop(crop, profile: profile, expectedSource: source)
                    } failure: {
                        draft.reportFailure($0)
                    } activity: { identifier, isActive in
                        draft.setCropping(identifier, isActive: isActive)
                    }
                    .id(PreviewIdentity(image: ObjectIdentifier(source.image), isMirrored: source.isMirrored))
                    Text("\(source.image.width) × \(source.image.height) pixels · Drag to select a crop")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach(0..<4, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(["X", "Y", "Width", "Height"][index]).font(.caption)
                                TextField("", text: $values[index])
                                    .accessibilityLabel(
                                        "\(profile.rawValue) crop \(["X", "Y", "Width", "Height"][index])")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Button("Use Full Image") { draft.useFullImage(profile) }
                } else {
                    ContentUnavailableView("No \(profile.rawValue) source", systemImage: "photo").frame(height: 180)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: source?.displayedCrop, initial: true) { _, crop in
            values = crop.map { [$0.x, $0.y, $0.width, $0.height].map(String.init) } ?? ["", "", "", ""]
        }
        .onChange(of: draft.sourceEpoch) { _, _ in
            values =
                source.map {
                    [$0.displayedCrop.x, $0.displayedCrop.y, $0.displayedCrop.width, $0.displayedCrop.height].map(
                        String.init)
                }
                ?? ["", "", "", ""]
        }
        .onChange(of: values) { _, values in draft.setCrop(profile: profile, values: values) }
    }
}

private struct PreviewIdentity: Hashable {
    let image: ObjectIdentifier
    let isMirrored: Bool
}

private struct ReferenceCropPreview: View {
    let source: ReferenceCompositionSource
    let select: (ReferenceImageCrop) -> Void
    let failure: (Error) -> Void
    let activity: (UUID, Bool) -> Void
    @State private var gestureIdentity = UUID()
    @GestureState private var drag: DragGesture.Value?

    var body: some View {
        GeometryReader { geometry in
            if let projection = try? ReferenceCropProjection(
                size: source.crop.size, width: geometry.size.width, height: geometry.size.height)
            {
                ZStack(alignment: .topLeading) {
                    Color.secondary.opacity(0.1)
                    Image(decorative: source.image, scale: 1).resizable()
                        .scaleEffect(x: source.isMirrored ? -1 : 1, y: 1)
                        .frame(width: projection.imageWidth, height: projection.imageHeight)
                        .offset(x: projection.imageX, y: projection.imageY)
                    let crop = tentativeCrop(projection) ?? source.displayedCrop
                    Rectangle().stroke(.blue, lineWidth: 2)
                        .frame(
                            width: Double(crop.width) * projection.imageWidth / Double(source.image.width),
                            height: Double(crop.height) * projection.imageHeight / Double(source.image.height)
                        )
                        .offset(
                            x: projection.imageX + Double(crop.x) * projection.imageWidth / Double(source.image.width),
                            y: projection.imageY + Double(crop.y) * projection.imageHeight / Double(source.image.height)
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3).updating($drag) { value, state, _ in state = value }
                        .onEnded { value in
                            do {
                                select(try projection.crop(from: point(value.startLocation), to: point(value.location)))
                            } catch { failure(error) }
                        })
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Profile crop preview; use crop fields for keyboard editing")
        .onChange(of: drag != nil) { _, isActive in activity(gestureIdentity, isActive) }
        .onDisappear { activity(gestureIdentity, false) }
    }

    private func point(_ point: CGPoint) -> CanvasPoint { .init(x: point.x, y: point.y) }
    private func tentativeCrop(_ projection: ReferenceCropProjection) -> ReferenceImageCrop? {
        // A subpixel or cancelled tentative rectangle is expected to be empty; only End validates an edit.
        drag.flatMap { try? projection.crop(from: point($0.startLocation), to: point($0.location)) }
    }
}
