import AppKit
import os
import SwiftUI

private let log = Logger(subsystem: "local.lumen.Lumen", category: "drop")

/// Hosting view that accepts dropped files anywhere in the window.
///
/// SwiftUI's `dropDestination` on the root view missed drops that landed on the scroll view
/// and its buttons; handling the drag at the AppKit level covers every point of the window.
final class FileDropHostingView<Content: View>: NSHostingView<Content> {
    var onDropFiles: (([URL]) -> Void)?
    var onTargetedChange: ((Bool) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        onTargetedChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetedChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetedChange?(false)
        let urls = fileURLs(from: sender)
        log.info("Dropped \(urls.count, privacy: .public) file(s): \(urls.map(\.lastPathComponent).joined(separator: ", "), privacy: .public)")
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}
