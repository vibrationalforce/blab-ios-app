// ShareSheet.swift
// Echoel — the system share sheet (UIActivityViewController) used to hand an
// exported file (e.g. a .mid from BeatTab) to another app. Tiny, self-contained
// wrapper; lives here in the active Studio flow.

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
