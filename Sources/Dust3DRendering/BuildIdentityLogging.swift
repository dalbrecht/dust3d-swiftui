import OSLog

extension RuntimeBuildIdentity {
    /// Emit startup provenance without document names, paths or user information.
    /// - Parameter subsystem: The owning app's logging subsystem.
    public func logStartup(subsystem: String) {
        let logger = Logger(subsystem: subsystem, category: "build-identity")
        switch metadata {
        case .success(let build):
            logger.info(
                "operation=appStartup pid=\(processIdentifier) source_revision=\(build.sourceRevision, privacy: .public) source_digest=\(build.sourceDigest, privacy: .public) core_revision=\(build.coreRevision, privacy: .public) is_dirty=\(build.isDirty)"
            )
        case .failure(let cause):
            logger.error(
                "operation=appStartup pid=\(processIdentifier) build_identity=unavailable cause=\(cause.localizedDescription, privacy: .public)"
            )
        }
    }
}
