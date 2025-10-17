import SwiftUI
import UIKit

struct MissionLogShareButton: View {
    let logURL: URL
    @State private var isPresenting = false

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: logURL) {
                Label("Export Log", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MissionSecondaryButtonStyle())
        } else {
            Button {
                isPresenting = true
            } label: {
                Label("Export Log", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MissionSecondaryButtonStyle())
            .sheet(isPresented: $isPresenting) {
                ActivityViewController(activityItems: [logURL])
            }
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MissionLogShareButton(logURL: URL(fileURLWithPath: "/tmp/mock.json"))
        .padding()
        .previewLayout(.sizeThatFits)
}
