import SwiftUI
import UniformTypeIdentifiers

struct EditorSessionDiagnosticsView: View {
    let diagnostics: EditorSessionDiagnostics
    @State private var report: SessionDiagnosticsReport?
    @State private var isExporting = false
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            if diagnostics.entries.isEmpty {
                ContentUnavailableView("No Session Events", systemImage: "text.alignleft")
            } else {
                List(diagnostics.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            entry.event.rawValue,
                            systemImage: entry.event.isFailure ? "exclamationmark.circle" : "info.circle")
                        Text(entry.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .textSelection(.enabled)
                }
            }
            Text("Only recent editor outcomes are included. Document contents and paths are excluded.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Clear Log") { diagnostics.clear() }
                    .disabled(diagnostics.entries.isEmpty)
                Spacer()
                Button("Save Log…") {
                    report = SessionDiagnosticsReport(text: diagnostics.exportText)
                    isExporting = true
                }
                .disabled(diagnostics.entries.isEmpty || isExporting)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
        .fileExporter(
            isPresented: $isExporting, document: report, contentTypes: [.plainText],
            defaultFilename: "Mote3D Session Log",
            onCompletion: { result in
                report = nil
                saveErrorMessage = Self.saveFailureMessage(for: result)
            },
            onCancellation: { report = nil }
        )
        .alert(
            "Could Not Save Session Log",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }),
            presenting: saveErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { cause in
            Text(verbatim: cause)
        }
    }

    static func saveFailureMessage(for result: Result<URL, any Error>) -> String? {
        guard case .failure(let cause) = result, !(cause is CancellationError),
            (cause as? CocoaError)?.code != .userCancelled
        else { return nil }
        return cause.localizedDescription
    }
}

private struct SessionDiagnosticsReport: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
