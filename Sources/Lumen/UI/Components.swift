import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0D / 255)
    static let tileRadius: CGFloat = 8
}

/// Small in-memory cache so thumbnails are not re-read from disk on every redraw.
@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Thumbnail with a 16:10 shape and a white outline when it is the current wallpaper.
struct ThumbnailTile: View {
    let url: URL?
    var isCurrent = false

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let url, let image = ThumbnailCache.image(at: url) {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileRadius)
                    .strokeBorder(Color.white, lineWidth: isCurrent ? 2 : 0)
            }
    }
}

/// Dashed "＋" tile.
struct AddTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Theme.tileRadius)
                .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus").font(.title2).foregroundStyle(.white.opacity(0.6))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rounded pill button; `prominent` draws it white on black like the hero's main action.
struct PillButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .background(prominent ? Color.white : Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
