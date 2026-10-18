import Foundation
import MachO

/// A process-lifetime copy of metadata from the loaded executable, never the replaceable app bundle.
public struct RuntimeBuildIdentity: Sendable {
    public let metadata: Result<BuildIdentityMetadata, BuildIdentityError>
    public let launchBundleIdentifier: String?
    public let processIdentifier: Int32
    /// Time of the startup capture, distinct from a build timestamp or kernel process start time.
    public let capturedAt: Date

    /// Apps read this value during initialization and retain it for diagnostics and startup logging.
    public static let current = capture()

    init(metadataData: Data?, processIdentifier: Int32, capturedAt: Date, launchBundleIdentifier: String? = nil) {
        self.launchBundleIdentifier = launchBundleIdentifier
        self.processIdentifier = processIdentifier
        self.capturedAt = capturedAt
        do {
            guard let metadataData else { throw BuildIdentityError.missing }
            metadata = .success(try BuildIdentityMetadata(data: metadataData))
        } catch let cause as BuildIdentityError {
            metadata = .failure(cause)
        } catch {
            metadata = .failure(.decoding(cause: error))
        }
    }

    private init(
        cause: BuildIdentityError, processIdentifier: Int32, capturedAt: Date, launchBundleIdentifier: String? = nil
    ) {
        metadata = .failure(cause)
        self.launchBundleIdentifier = launchBundleIdentifier
        self.processIdentifier = processIdentifier
        self.capturedAt = capturedAt
    }

    private static func capture() -> RuntimeBuildIdentity {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let capturedAt = Date()
        let launchBundleIdentifier = Bundle.main.bundleIdentifier
        do {
            return RuntimeBuildIdentity(
                metadataData: try embeddedData(), processIdentifier: processIdentifier, capturedAt: capturedAt,
                launchBundleIdentifier: launchBundleIdentifier)
        } catch let cause as BuildIdentityError {
            return RuntimeBuildIdentity(
                cause: cause, processIdentifier: processIdentifier, capturedAt: capturedAt,
                launchBundleIdentifier: launchBundleIdentifier)
        } catch {
            return RuntimeBuildIdentity(
                cause: .decoding(cause: error), processIdentifier: processIdentifier, capturedAt: capturedAt,
                launchBundleIdentifier: launchBundleIdentifier)
        }
    }

    private static func embeddedData() throws -> Data? {
        guard let header = _dyld_get_image_header(0), header.pointee.magic == MH_MAGIC_64 else { return nil }
        // Supported native macOS targets are 64-bit; the OS loader owns this validated, mapped image.
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        var size: UInt = 0
        guard let bytes = getsectiondata(header64, "__TEXT", "__dust3d_build", &size) else { return nil }
        guard size <= 4096 else { throw BuildIdentityError.oversized(Int(clamping: size)) }
        return Data(bytes: bytes, count: Int(size))
    }
}
