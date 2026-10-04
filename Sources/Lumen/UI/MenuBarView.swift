import LumenCore
import SwiftUI

/// Popover shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let openWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThumbnailTile(url: model.currentVideoID.map(model.thumbnailURL(for:)))

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
                controlButton(model.isPlaying ? "pause.fill" : "play.fill", label: model.isPlaying ? "Pause" : "Lecture",
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
            toggle("Écran de verrouillage animé", \.lockScreenEnabled)
            toggle("Pause sur batterie", \.pauseOnBattery)
            toggle("Lecture aléatoire", \.shuffle)
            Divider()

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

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<LumenCore.Settings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.library.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        ))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(size: 12))
    }
}
