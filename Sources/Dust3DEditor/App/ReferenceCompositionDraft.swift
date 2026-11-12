import CoreGraphics
import Dust3DEditorModel
import Foundation
import Observation

enum ReferenceProfile: String, CaseIterable, Sendable {
    case front = "Front"
    case side = "Side"
}

/// Ordered local image URLs delivered together by the drop target.
struct ReferenceCompositionDrop {
    let front: URL
    let side: URL?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp", "gif", "tif", "tiff"]

    init?(urls: [URL]) {
        guard (1...2).contains(urls.count), let first = urls.first,
            urls.allSatisfy({ url in
                url.isFileURL
                    && (url.host(percentEncoded: false).map { $0.isEmpty || $0.lowercased() == "localhost" } ?? true)
                    && Self.imageExtensions.contains(url.pathExtension.lowercased())
            })
        else { return nil }
        front = first
        side = urls.dropFirst().first
    }
}

/// A sheet owns this transient state; no draft action can access or mutate an editor session.
@MainActor @Observable final class ReferenceCompositionDraft {
    private(set) var front: ReferenceCompositionSource?
    private(set) var side: ReferenceCompositionSource?
    private(set) var result: ReferenceCompositionResult?
    private(set) var isWorking = false
    private enum Issue {
        case general(String)
        case numericCrop(ReferenceProfile, String)

        var message: String {
            switch self {
            case .general(let message), .numericCrop(_, let message): message
            }
        }
    }

    private var issue: Issue?
    var errorMessage: String? { issue?.message }

    func announcementMessage(editingCrop profile: ReferenceProfile?) -> String? {
        if case .numericCrop(let invalidProfile, _)? = issue, profile == invalidProfile { return nil }
        return errorMessage
    }
    private(set) var sourceEpoch = 0
    private let service: any ReferenceCompositionServing
    private var operation: Task<Void, Never>?
    private var requestID = UUID()
    private var stopped = false
    private var activeCrops: Set<UUID> = []
    var canApply: Bool { result != nil && !isWorking && activeCrops.isEmpty && !stopped }

    func setCropping(_ identifier: UUID, isActive: Bool) {
        guard !stopped else { return }
        if isActive { activeCrops.insert(identifier) } else { activeCrops.remove(identifier) }
    }

    init(service: any ReferenceCompositionServing = ReferenceCompositionService()) { self.service = service }

    func source(_ profile: ReferenceProfile) -> ReferenceCompositionSource? { profile == .front ? front : side }

    func importSource(url: URL, profile: ReferenceProfile) {
        guard !stopped else { return }
        let retainedResult = result
        invalidate()
        result = retainedResult
        isWorking = true
        issue = nil
        let request = requestID
        operation = Task {
            do {
                let source = try await service.importSource(url: url)
                guard !Task.isCancelled, !stopped, request == requestID else { return }
                assign(source, to: profile)
                sourceEpoch += 1
                render()
            } catch {
                guard !Task.isCancelled, !stopped, request == requestID else { return }
                isWorking = false
                issue = .general(EditorStore.message(error))
            }
        }
    }

    /// Stage both dropped profiles and their composition before publishing any of them.
    func importDroppedSources(_ drop: ReferenceCompositionDrop) {
        guard !stopped else { return }
        let retainedResult = result
        invalidate()
        result = retainedResult
        isWorking = true
        issue = nil
        let request = requestID
        operation = Task {
            do {
                let front = try await service.importSource(url: drop.front)
                try Task.checkCancellation()
                let side =
                    if let sideURL = drop.side {
                        try await service.importSource(url: sideURL) as ReferenceCompositionSource?
                    } else {
                        nil as ReferenceCompositionSource?
                    }
                try Task.checkCancellation()
                let composed = try await service.compose(front: front, side: side)
                guard !Task.isCancelled, !stopped, request == requestID else { return }
                self.front = front
                self.side = side
                result = composed
                sourceEpoch += 1
                isWorking = false
            } catch {
                guard !Task.isCancelled, !stopped, request == requestID else { return }
                isWorking = false
                issue = .general(EditorStore.message(error))
            }
        }
    }

    func useExisting(_ image: CGImage) {
        guard !stopped else { return }
        do {
            front = try ReferenceCompositionSource(
                image: image, crop: .init(size: .init(width: image.width, height: image.height)))
            sourceEpoch += 1
            render()
        } catch { fail(error) }
    }

    func setCrop(profile: ReferenceProfile, values: [String]) {
        guard !stopped, let source = source(profile) else { return }
        do {
            let numbers = values.compactMap(Int.init)
            guard numbers.count == 4, values.count == 4 else { throw ReferenceCompositionError.invalidCrop }
            let displayed = try ReferenceImageCrop(
                size: source.crop.size, x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            applyCrop(displayed, profile: profile, source: source)
        } catch {
            invalidate()
            issue = .numericCrop(profile, EditorStore.message(error))
        }
    }

    private func applyCrop(
        _ displayed: ReferenceImageCrop, profile: ReferenceProfile, source: ReferenceCompositionSource
    ) {
        do {
            let crop = source.isMirrored ? displayed.mirroredHorizontally : displayed
            if crop == source.crop && issue == nil { return }
            assign(
                try .init(
                    image: source.image, crop: crop, isMirrored: source.isMirrored, straightRGBA: source.straightRGBA,
                    isIndexed: source.isIndexed, wideImage: source.wideImage),
                to: profile)
            render()
        } catch { fail(error) }
    }

    func setPointerCrop(
        _ crop: ReferenceImageCrop, profile: ReferenceProfile, expectedSource: ReferenceCompositionSource
    ) {
        guard let current = source(profile), current.image === expectedSource.image,
            current.crop == expectedSource.crop, current.isMirrored == expectedSource.isMirrored
        else { return }
        do {
            let displayed = try ReferenceImageCrop(
                size: current.crop.size, x: crop.x, y: crop.y, width: crop.width, height: crop.height)
            applyCrop(displayed, profile: profile, source: current)
        } catch { fail(error) }
        sourceEpoch += 1
    }

    func useFullImage(_ profile: ReferenceProfile) {
        guard !stopped, let source = source(profile) else { return }
        applyCrop(ReferenceImageCrop(size: source.crop.size), profile: profile, source: source)
        sourceEpoch += 1
    }

    func reportRejectedInput(_ error: Error) {
        guard !stopped else { return }
        issue = .general(EditorStore.message(error))
    }

    func swapProfiles() {
        guard !stopped else { return }
        swap(&front, &side)
        sourceEpoch += 1
        render()
    }

    func toggleSideMirror() {
        guard !stopped, let side else { return }
        do {
            self.side = try .init(
                image: side.image, crop: side.crop, isMirrored: !side.isMirrored, straightRGBA: side.straightRGBA,
                isIndexed: side.isIndexed, wideImage: side.wideImage)
            sourceEpoch += 1
            render()
        } catch { fail(error) }
    }

    func remove(_ profile: ReferenceProfile) {
        guard !stopped else { return }
        assign(nil, to: profile)
        sourceEpoch += 1
        render()
    }

    func stop() {
        stopped = true
        activeCrops.removeAll()
        invalidate()
        front = nil
        side = nil
        issue = nil
    }

    private func assign(_ source: ReferenceCompositionSource?, to profile: ReferenceProfile) {
        if profile == .front { front = source } else { side = source }
    }

    private func invalidate() {
        operation?.cancel()
        operation = nil
        requestID = UUID()
        isWorking = false
        result = nil
    }

    private func fail(_ error: Error) {
        invalidate()
        issue = .general(EditorStore.message(error))
    }

    private func render() {
        invalidate()
        issue = nil
        guard front != nil || side != nil else { return }
        isWorking = true
        let request = requestID
        let front = front
        let side = side
        operation = Task {
            do {
                let result = try await service.compose(front: front, side: side)
                guard !Task.isCancelled, !stopped, request == requestID else { return }
                self.result = result
                isWorking = false
            } catch {
                guard !Task.isCancelled, !stopped, request == requestID else { return }
                isWorking = false
                issue = .general(EditorStore.message(error))
            }
        }
    }
}
