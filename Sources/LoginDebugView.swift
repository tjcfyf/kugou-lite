import SwiftUI
import UIKit

struct LoginDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationView {
            ScrollView {
                Text(LoginDebug.shared.maskedText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("QQ 登录日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("分享") { showShare = true }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityView(items: [LoginDebug.shared.fileURL])
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
