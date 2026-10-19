import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class ImportedMaterialCopyTests: XCTestCase {
    private func material(_ edit: (inout Dust3DImportedMaterialView) -> Void = { _ in }) throws -> ImportedModelMaterial
    {
        try "{00000300-0000-4000-8000-000000000300}".withCString { identity in
            var view = Dust3DImportedMaterialView()
            view.model_id = identity
            view.base_color = (1, 1, 1, 1)
            view.emissive = (0, 0, 0)
            view.alpha_mode = DUST3D_IMPORTED_ALPHA_OPAQUE
            edit(&view)
            var budget = ImportedCopyBudget(maximum: 4096)
            return try ImportedMaterialCopy.material(view, budget: &budget)
        }
    }

    func test_should_validate_factor_ranges_alpha_and_presence_flags() throws {
        for (native, expected) in [
            (DUST3D_IMPORTED_ALPHA_OPAQUE, ImportedAlphaMode.opaque),
            (DUST3D_IMPORTED_ALPHA_MASK, .mask),
            (DUST3D_IMPORTED_ALPHA_BLEND, .blend),
        ] {
            XCTAssertEqual(try material { $0.alpha_mode = native }.alphaMode, expected)
        }
        XCTAssertTrue(try material { $0.is_double_sided = 1 }.isDoubleSided)
        let edits: [(inout Dust3DImportedMaterialView) -> Void] = [
            { $0.base_color.0 = -.infinity }, { $0.base_color.3 = 1.1 },
            { $0.metallic = .nan }, { $0.roughness = -0.1 },
            { $0.emissive.1 = 2 }, { $0.alpha_cutoff = -.infinity },
            { $0.is_double_sided = 2 }, { $0.alpha_mode = .init(rawValue: 999) },
        ]
        for edit in edits {
            XCTAssertThrowsError(try material(edit)) {
                XCTAssertEqual($0 as? ImportedMaterialError, .invalidMaterial)
            }
        }
        XCTAssertNil(try material().image)
        XCTAssertNil(try material().sampler)
        XCTAssertThrowsError(
            try material {
                $0.has_sampler = 1
                $0.wrap_s = 10497
                $0.wrap_t = 10497
            }
        ) {
            XCTAssertEqual($0 as? ImportedMaterialError, .invalidImage)
        }
    }

    func test_should_preserve_sampler_choices_and_reject_inconsistent_fields() throws {
        var value = Dust3DImportedMaterialView()
        XCTAssertNil(try ImportedMaterialCopy.sampler(value))
        value.has_sampler = 1
        value.wrap_s = 10497
        value.wrap_t = 33071
        XCTAssertEqual(try ImportedMaterialCopy.sampler(value)?.wrapS, .repeatTexture)
        for filter in ImportedMagnificationFilter.allCases {
            value.has_magnification_filter = 1
            value.magnification_filter = filter.rawValue
            XCTAssertEqual(try ImportedMaterialCopy.sampler(value)?.magnification, filter)
        }
        for filter in ImportedMinificationFilter.allCases {
            value.has_minification_filter = 1
            value.minification_filter = filter.rawValue
            XCTAssertEqual(try ImportedMaterialCopy.sampler(value)?.minification, filter)
        }
        for wrapping in ImportedTextureWrapMode.allCases {
            value.wrap_s = wrapping.rawValue
            value.wrap_t = wrapping.rawValue
            XCTAssertEqual(try ImportedMaterialCopy.sampler(value)?.wrapT, wrapping)
        }
        let edits: [(inout Dust3DImportedMaterialView) -> Void] = [
            { $0.has_sampler = 2 }, { $0.has_magnification_filter = 2 }, { $0.has_minification_filter = 2 },
            { $0.has_sampler = 0 }, { $0.wrap_s = 123 }, { $0.wrap_t = 123 },
            { $0.magnification_filter = 123 }, { $0.minification_filter = 123 },
            { $0.has_magnification_filter = 0 }, { $0.has_minification_filter = 0 },
        ]
        for edit in edits {
            var invalid = value
            edit(&invalid)
            XCTAssertThrowsError(try ImportedMaterialCopy.sampler(invalid)) {
                XCTAssertEqual($0 as? ImportedMaterialError, .invalidSampler)
            }
        }
        var absent = Dust3DImportedMaterialView()
        absent.wrap_s = 10497
        XCTAssertThrowsError(try ImportedMaterialCopy.sampler(absent))
    }

    func test_should_copy_only_consistent_bounded_image_views() throws {
        let bytes: [UInt8] = [1, 2, 3, 4]
        try bytes.withUnsafeBufferPointer { storage in
            try "image/png".withCString { mime in
                var view = Dust3DImportedEncodedImageView()
                view.mime_type = mime
                view.bytes = storage.baseAddress
                view.byte_count = storage.count
                var budget = ImportedCopyBudget(maximum: 4)
                let copied = try XCTUnwrap(ImportedMaterialCopy.image(view, budget: &budget))
                XCTAssertEqual(copied.bytes, Data(bytes))
                XCTAssertEqual(copied.encoding, .png)
                let edits: [(inout Dust3DImportedEncodedImageView) -> Void] = [
                    { $0.mime_type = nil }, { $0.bytes = nil },
                    { $0.byte_count = 0 }, { $0.byte_count = 16 * 1024 * 1024 + 1 },
                ]
                for edit in edits {
                    var invalid = view
                    edit(&invalid)
                    var remaining = ImportedCopyBudget(maximum: 32)
                    XCTAssertThrowsError(try ImportedMaterialCopy.image(invalid, budget: &remaining)) {
                        XCTAssertEqual($0 as? ImportedMaterialError, .invalidImage)
                    }
                }
                var tiny = ImportedCopyBudget(maximum: 3)
                XCTAssertThrowsError(try ImportedMaterialCopy.image(view, budget: &tiny)) {
                    XCTAssertEqual($0 as? ImportedMaterialError, .copyLimitExceeded)
                }
                try "text/plain".withCString { invalidMime in
                    view.mime_type = invalidMime
                    var remaining = ImportedCopyBudget(maximum: 32)
                    XCTAssertThrowsError(try ImportedMaterialCopy.image(view, budget: &remaining))
                }
                var invalidUTF8: [CChar] = [-1, 0]
                try invalidUTF8.withUnsafeMutableBufferPointer { invalid in
                    view.mime_type = UnsafePointer(invalid.baseAddress)
                    var remaining = ImportedCopyBudget(maximum: 32)
                    XCTAssertThrowsError(try ImportedMaterialCopy.image(view, budget: &remaining))
                }
            }
        }
        var budget = ImportedCopyBudget(maximum: 32)
        XCTAssertNil(try ImportedMaterialCopy.image(Dust3DImportedEncodedImageView(), budget: &budget))
    }

    func test_should_check_counts_identity_bytes_and_arithmetic_before_copying() throws {
        for (models, bindings, payload, limit) in [
            (-1, 0, 1, 1), (0, -1, 1, 1), (0, 0, 0, 1),
            (0, 0, 2, 1), (Int.max, 0, 1024, 1024), (0, Int.max, 1024, 1024),
        ] {
            XCTAssertThrowsError(
                try ImportedMaterialCopy.validateCounts(
                    models: models, bindings: bindings, payload: payload, nativeMaximum: limit)
            ) {
                XCTAssertEqual($0 as? ImportedMaterialError, .invalidNativeCounts)
            }
        }
        XCTAssertNoThrow(try ImportedMaterialCopy.validateCounts(models: 0, bindings: 0, payload: 1, nativeMaximum: 1))
        var budget = ImportedCopyBudget(maximum: 4)
        XCTAssertThrowsError(try budget.charge(-1))
        XCTAssertThrowsError(try budget.charge(1, width: 0))
        XCTAssertThrowsError(try budget.charge(Int.max, width: 2))
        XCTAssertNoThrow(try budget.charge(4))
        XCTAssertEqual(budget.used, 4)
        XCTAssertThrowsError(try budget.charge(1))
        XCTAssertThrowsError(try ImportedMaterialCopy.identity(nil, budget: &budget)) {
            XCTAssertEqual($0 as? ImportedMaterialError, .invalidIdentity)
        }
        XCTAssertThrowsError(try ImportedMaterialLoader.validate(dataCount: Int.max, options: .init())) {
            XCTAssertEqual($0 as? ImportedMaterialError, .archiveLimitExceeded)
        }
        XCTAssertThrowsError(try ImportedMaterialLoader.validate(dataCount: -1, options: .init()))
        XCTAssertThrowsError(
            try ImportedMaterialLoader.validate(
                dataCount: 1, options: .init(maximumCopiedPayloadBytes: 256 * 1024 * 1024 + 1)))
        for error in ImportedMaterialError.allCases {
            XCTAssertFalse(try XCTUnwrap(error.errorDescription).isEmpty)
        }
    }

    func test_should_validate_bindings_without_uuid_or_unicode_collapse() throws {
        func binding(_ component: String?, _ part: String = "part", _ model: String = "model")
            -> ImportedMaterialBinding
        {
            ImportedMaterialBinding(componentID: component, partID: part, modelID: model)
        }
        let first = binding("first")
        let second = binding("second")
        XCTAssertNoThrow(try ImportedMaterialCopy.validateBindings([first, second]))
        for invalid in [
            [first, first], [first, binding("second", "part", "different")],
            [binding(nil), first], [first, binding(nil)], [binding(nil), binding(nil)],
        ] {
            XCTAssertThrowsError(try ImportedMaterialCopy.validateBindings(invalid)) {
                XCTAssertEqual($0 as? ImportedMaterialError, .invalidBinding)
            }
        }
        XCTAssertNoThrow(try ImportedMaterialCopy.validateBindings([binding(nil, "é"), binding(nil, "e\u{301}")]))
        XCTAssertEqual(binding(nil), binding(nil))
        XCTAssertNotEqual(binding(nil), first)
        XCTAssertNotEqual(first, binding(nil))
        XCTAssertNotEqual(binding("é"), binding("e\u{301}"))
        XCTAssertNotEqual(first, binding("first", "different"))
        XCTAssertNotEqual(first, binding("first", "part", "different"))
        XCTAssertEqual(first, binding("first"))
    }
}
