import Dust3DKit
import Foundation

/// The authored template listing can run before the application owns any windows.
enum EditorRigListCommand {
    private static let option = "-list-rigs"
    private static let templateTypes = ["Biped", "Quadruped", "Bird", "Fish", "Insect", "Snake", "Spider"]

    private enum Failure: LocalizedError {
        case invalidUsage
        case unavailableTemplate(String)
        case unreadableTemplate(String, cause: String)
        case invalidTemplate(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidUsage: "Usage: Dust3DEditor -list-rigs"
            case .unavailableTemplate(let type): "Rig template \(type) is unavailable."
            case .unreadableTemplate(let type, let cause): "Could not read rig template \(type). \(cause)"
            case .invalidTemplate(let type): "Rig template \(type) does not contain valid UTF-8 XML text."
            case .writeFailed(let cause): "Could not write the rig list. \(cause)"
            }
        }
    }

    /// Nil leaves the ordinary application and recovery launch routes in charge.
    static func run(
        arguments: [String],
        load: (String) throws -> Data? = RigTemplateResources.data(forSourceType:),
        stdout: (Data) throws -> Void,
        stderr: (String) -> Void
    ) -> Int32? {
        let options = arguments.dropFirst()
        guard options.prefix(while: { $0 != "--" }).contains(option) else { return nil }
        guard options.elementsEqual([option]) else {
            stderr(Failure.invalidUsage.localizedDescription + "\n")
            return 2
        }

        do {
            let bodies = try templateTypes.map { try templateBody(type: $0, load: load) }
            let document =
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rigs>\n"
                + bodies.joined(separator: "\n") + "\n</rigs>\n"
            do {
                try stdout(Data(document.utf8))
            } catch { throw Failure.writeFailed(error.localizedDescription) }
            return 0
        } catch {
            stderr(error.localizedDescription + "\n")
            return 1
        }
    }

    private static func templateBody(type: String, load: (String) throws -> Data?) throws -> String {
        let data: Data?
        do {
            data = try load(type)
        } catch { throw Failure.unreadableTemplate(type, cause: error.localizedDescription) }
        guard let data else { throw Failure.unavailableTemplate(type) }
        guard let xml = String(data: data, encoding: .utf8) else { throw Failure.invalidTemplate(type) }
        let body: Substring
        if xml.hasPrefix("<?xml ") {
            guard let declarationEnd = xml.range(of: "?>") else { throw Failure.invalidTemplate(type) }
            body = xml[declarationEnd.upperBound...]
        } else {
            body = xml[...]
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.invalidTemplate(type) }
        return trimmed
    }
}
