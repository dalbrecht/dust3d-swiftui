import Dust3DDocument
import SwiftUI
import UniformTypeIdentifiers

/// Native document scenes own open/save, file coordination and unsaved-close prompts.
struct EditorFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(importedAs: "org.dust3d.document")] }
    let identity = UUID()
    var data: Data

    init() { data = Dust3DDocument.emptyArchive() }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        _ = try Dust3DDocument(data: data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
