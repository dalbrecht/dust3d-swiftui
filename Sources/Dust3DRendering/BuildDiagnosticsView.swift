import SwiftUI

/// Read-only, selectable diagnostics for the identity retained by the current app process.
public struct BuildDiagnosticsView: View {
    private let applicationName: String
    private let presentation: BuildIdentityPresentation

    /// Show source/core revisions separately from process and startup-capture information.
    /// - Parameters:
    ///   - applicationName: Human-readable app name, including the QA distinction where appropriate.
    ///   - identity: Immutable startup identity, never reloaded from an on-disk bundle.
    public init(applicationName: String, identity: RuntimeBuildIdentity) {
        self.applicationName = applicationName
        presentation = BuildIdentityPresentation(identity: identity)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(applicationName).font(.title2).fontWeight(.semibold)
                Label(
                    presentation.status,
                    systemImage: presentation.failureDescription == nil ? "info.circle" : "exclamationmark.triangle")
                if let cause = presentation.failureDescription {
                    Text(cause).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(presentation.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.label).font(.caption).foregroundStyle(.secondary)
                        Text(row.value).font(.system(.body, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.label)
                    .accessibilityValue(row.value)
                    .accessibilityIdentifier("build-identity-\(row.id)")
                }
                Text(
                    "Identity is retained from the loaded executable. Rebuilding the app bundle does not change this process’s capture."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}
