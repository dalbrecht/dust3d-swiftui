import Foundation
import XCTest

@testable import Dust3DRendering

final class RuntimeBuildIdentityTests: XCTestCase {
    func testShouldDecodeEmbeddedIdentityWithoutConsultingBundleMetadata() throws {
        let identity = try BuildIdentityMetadata(data: metadata())
        XCTAssertEqual(identity.sourceRevision, String(repeating: "a", count: 40))
        XCTAssertEqual(identity.coreRevision, String(repeating: "b", count: 40))
        XCTAssertEqual(identity.sourceDigest, String(repeating: "c", count: 64))
        XCTAssertTrue(identity.isDirty)
        XCTAssertEqual(identity.summary, "Modified source tree")
    }

    func testShouldExposeValidatedLocalCoreIdentity() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata()) as? [String: Any])
        payload["coreDigest"] = String(repeating: "d", count: 64)
        payload["coreIsDirty"] = true
        let identity = try BuildIdentityMetadata(data: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(identity.coreDigest, String(repeating: "d", count: 64))
        XCTAssertEqual(identity.coreIsDirty, true)
        payload["coreDigest"] = "invalid"
        XCTAssertThrowsError(try BuildIdentityMetadata(data: JSONSerialization.data(withJSONObject: payload)))
        payload.removeValue(forKey: "coreDigest")
        XCTAssertThrowsError(try BuildIdentityMetadata(data: JSONSerialization.data(withJSONObject: payload)))
    }

    func testShouldRejectMalformedOversizedAndUnsupportedIdentity() throws {
        for data in [
            Data(), Data("{}".utf8), Data(repeating: 32, count: 4097),
            try metadata(schemaVersion: 2), try metadata(sourceRevision: "not-a-revision"),
            try metadata(sourceDigest: "short"),
        ] {
            XCTAssertThrowsError(try BuildIdentityMetadata(data: data)) { error in
                XCTAssertTrue(error is BuildIdentityError)
            }
        }
    }

    func testShouldKeepCapturedIdentityIndependentOfLaterMetadataChanges() throws {
        var bytes = try metadata()
        let first = try BuildIdentityMetadata(data: bytes)
        bytes = try metadata(sourceRevision: String(repeating: "d", count: 40), isDirty: false)
        let second = try BuildIdentityMetadata(data: bytes)
        XCTAssertEqual(first.sourceRevision, String(repeating: "a", count: 40))
        XCTAssertEqual(second.sourceRevision, String(repeating: "d", count: 40))
        XCTAssertEqual(second.summary, "Clean source tree")
        XCTAssertNotEqual(first, second)
    }

    func testShouldKeepMissingIdentityExplicitAndRetainProcessContext() {
        let captured = RuntimeBuildIdentity(
            metadataData: nil, processIdentifier: 42, capturedAt: Date(timeIntervalSince1970: 123))
        XCTAssertEqual(captured.processIdentifier, 42)
        XCTAssertEqual(captured.capturedAt, Date(timeIntervalSince1970: 123))
        guard case .failure(let cause) = captured.metadata else { return XCTFail("Missing metadata was invented") }
        XCTAssertEqual(cause.localizedDescription, "This executable has no embedded build identity.")
    }

    func testShouldCopyMetadataIntoAnImmutableProcessSnapshot() throws {
        let captured = RuntimeBuildIdentity(
            metadataData: try metadata(), processIdentifier: 7, capturedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(try captured.metadata.get().sourceRevision, String(repeating: "a", count: 40))
    }

    func testShouldPresentDistinctSourceCoreAndProcessFields() throws {
        let captured = RuntimeBuildIdentity(
            metadataData: try metadata(), processIdentifier: 7, capturedAt: Date(timeIntervalSince1970: 0))
        let presentation = BuildIdentityPresentation(identity: captured)
        XCTAssertEqual(
            presentation.rows.first { $0.label == "Source revision" }?.value, String(repeating: "a", count: 40))
        XCTAssertEqual(
            presentation.rows.first { $0.label == "Core revision" }?.value, String(repeating: "b", count: 40))
        XCTAssertEqual(presentation.rows.first { $0.label == "Process ID" }?.value, "7")
        XCTAssertEqual(presentation.status, "Modified source tree")
        XCTAssertNil(presentation.failureDescription)
    }

    func testShouldPresentUnavailableMetadataWithOriginalCause() {
        let captured = RuntimeBuildIdentity(
            metadataData: Data("{}".utf8), processIdentifier: 3, capturedAt: Date(timeIntervalSince1970: 0))
        let presentation = BuildIdentityPresentation(identity: captured)
        XCTAssertEqual(presentation.status, "Build identity unavailable")
        XCTAssertTrue(presentation.failureDescription?.contains("could not be decoded") == true)
        XCTAssertFalse(presentation.rows.contains { $0.label == "Source revision" })
    }

    func testShouldDistinguishQAAndCanonicalApplicationNames() {
        XCTAssertEqual(
            BuildIdentityPresentation.applicationName(
                bundleIdentifier: "org.dust3d.editor.combine-qa", fallback: "Dust3D Editor"), "Dust3D Editor QA")
        XCTAssertEqual(
            BuildIdentityPresentation.applicationName(bundleIdentifier: "org.dust3d.editor", fallback: "Dust3D Editor"),
            "Dust3D Editor")
        XCTAssertEqual(
            BuildIdentityPresentation.applicationName(bundleIdentifier: "org.dust3d.viewer", fallback: "Dust3D Viewer"),
            "Dust3D Viewer")
    }

    func testShouldRetainCallerNameWhenLaunchIdentityIsUnavailableOrUnknown() {
        for identifier in [nil, "org.example.unknown"] {
            XCTAssertEqual(
                BuildIdentityPresentation.applicationName(bundleIdentifier: identifier, fallback: "Dust3D Editor"),
                "Dust3D Editor")
        }
    }

    func testShouldRouteAllQAEventsThroughTheCapturedSubsystem() {
        let qa = RuntimeBuildIdentity(
            metadataData: nil, processIdentifier: 1, capturedAt: Date(),
            launchBundleIdentifier: "org.dust3d.editor.combine-qa")
        let canonical = RuntimeBuildIdentity(
            metadataData: nil, processIdentifier: 2, capturedAt: Date(), launchBundleIdentifier: "org.dust3d.editor")
        XCTAssertEqual(qa.loggingSubsystem(fallback: "org.dust3d.editor"), "org.dust3d.editor.combine-qa")
        XCTAssertEqual(canonical.loggingSubsystem(fallback: "org.dust3d.editor"), "org.dust3d.editor")
        XCTAssertNotEqual(
            qa.loggingSubsystem(fallback: "org.dust3d.editor"),
            canonical.loggingSubsystem(fallback: "org.dust3d.editor"))
    }

    func testShouldUseExplicitLogFallbackOnlyWhenCapturedBundleIdentityIsMissing() {
        let missing = RuntimeBuildIdentity(metadataData: nil, processIdentifier: 1, capturedAt: Date())
        let custom = RuntimeBuildIdentity(
            metadataData: nil, processIdentifier: 2, capturedAt: Date(), launchBundleIdentifier: "org.example.custom")
        XCTAssertEqual(missing.loggingSubsystem(fallback: "org.dust3d.viewer"), "org.dust3d.viewer")
        XCTAssertEqual(custom.loggingSubsystem(fallback: "org.dust3d.editor"), "org.example.custom")
    }

    private func metadata(
        schemaVersion: Int = 1, sourceRevision: String = String(repeating: "a", count: 40),
        sourceDigest: String = String(repeating: "c", count: 64), isDirty: Bool = true
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": schemaVersion, "sourceRevision": sourceRevision,
            "coreRevision": String(repeating: "b", count: 40), "sourceDigest": sourceDigest,
            "isDirty": isDirty,
        ])
    }
}
