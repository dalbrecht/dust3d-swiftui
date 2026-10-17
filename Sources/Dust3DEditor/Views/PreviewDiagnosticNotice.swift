import SwiftUI

enum PreviewDiagnosticKind: String, CaseIterable {
    case cache
    case source
    var title: String {
        switch self {
        case .cache: "Preview cache unavailable"
        case .source: "Preview details unavailable"
        }
    }
}

struct PreviewDiagnosticNotice: View {
    let kind: PreviewDiagnosticKind
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(kind.title, systemImage: "info.circle")
                .fontWeight(.medium)
            Text("Editing and saving remain available.")
            Text(message).textSelection(.enabled)
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preview-\(kind.rawValue)-notice")
    }
}
