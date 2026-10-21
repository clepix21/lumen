import LumenCore
import SwiftUI

/// Popover shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let openWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Full popover width (260 minus the 12-point padding on each side), 16:10.
            ThumbnailTile(url: model.currentVideoID.map(model.thumbnailURL(for:)))
                .frame(width: 236, height: 147.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentVideo?.name ?? "Aucune vidéo")
                    .font(.system(size: 13, weight: .semibold))
                if let position = model.positionText {
                    Text(position).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                controlButton("backward.fill", label: "Précédente", enabled: model.isInPlaylist) { model.previous() }
                Spacer()
                controlButton(model.userPaused ? "play.fill" : "pause.fill", label: model.userPaused ? "Lecture" : "Pause",
                              enabled: model.currentVideoID != nil) { model.togglePause() }
                Spacer()
                controlButton("forward.fill", label: "Suivante", enabled: model.isInPlaylist) { model.next() }
                Spacer()
                controlButton(model.library.settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                              label: "Son", enabled: true) { model.toggleMute() }
                Spacer()
            }
            .font(.system(size: 16))

            Divider()
            if #available(macOS 26, *) {
                toggle("Écran de verrouillage animé", \.lockScreenEnabled)
            }
            toggle("Pause sur batterie", \.pauseOnBattery)
            toggle("Lecture aléatoire", \.shuffle)
            Divider()

            if let update = model.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.pageURL)
                } label: {
                    Label("Mise à jour disponible : \(update.version)", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Divider()
            }

            HStack {
                Button("Ouvrir la fenêtre…", action: openWindow)
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func controlButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Label on the left, switch aligned on the right edge.
    private func toggle(_ title: String, _ keyPath: WritableKeyPath<LumenCore.Settings, Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle(title, isOn: Binding(
                get: { model.library.settings[keyPath: keyPath] },
                set: { value in model.update { $0[keyPath: keyPath] = value } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}
