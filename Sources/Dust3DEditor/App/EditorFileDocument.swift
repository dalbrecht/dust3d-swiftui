import Dust3DDocument
import SwiftUI
import UniformTypeIdentifiers

/// Native document scenes own open/save, file coordination and unsaved-close prompts.
struct EditorFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(importedAs: "org.dust3d.document")] }
    let identity = UUID()
    private let saveState: EditorSaveState
    private var saveVersion: UUID
    var data: Data { didSet { saveVersion = saveState.publish() } }

    init() { self.init(validatedData: Dust3DDocument.emptyArchive()) }

    init(data: Data) throws {
        _ = try Dust3DDocument(data: data)
        self.init(validatedData: data)
    }

    private init(validatedData: Data) {
        let version = UUID()
        saveState = EditorSaveState(version: version)
        saveVersion = version
        data = validatedData
    }

    func setEditing(_ isEditing: Bool) { saveState.setEditing(isEditing) }

    func dataForSaving() throws -> Data {
        try saveState.validate(saveVersion)
        return data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try dataForSaving())
    }
}
