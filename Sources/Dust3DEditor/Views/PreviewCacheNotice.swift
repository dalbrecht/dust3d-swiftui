import SwiftUI

struct PreviewCacheNotice: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Preview cache unavailable", systemImage: "info.circle")
                .fontWeight(.medium)
            Text("Editing and saving remain available.")
            Text(message).textSelection(.enabled)
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preview-cache-notice")
    }
}
