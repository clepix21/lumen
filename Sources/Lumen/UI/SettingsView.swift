import AppKit
import LumenCore
import SwiftUI

/// "Réglages" section.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group("Lecture") {
                    toggle("Son coupé", \.isMuted)
                    toggle("Lecture aléatoire dans les playlists", \.shuffle)
                }
                group("Économie d'énergie") {
                    toggle("Pause quand une app est en plein écran", \.pauseWhenOccluded)
                    toggle("Pause sur batterie", \.pauseOnBattery)
                }
                group("Système") {
                    toggle("Lancer au démarrage du Mac", \.launchAtLogin)
                    if #available(macOS 26, *) {
                        toggle("Écran de verrouillage animé", \.lockScreenEnabled)
                        Text("La vidéo du bureau s'affiche aussi sur l'écran de verrouillage, sans le son.")
                            .font(.system(size: 11)).opacity(0.6)
                    } else {
                        Toggle("Écran de verrouillage animé", isOn: .constant(false)).disabled(true)
                        Text("Nécessite macOS 26 ou plus récent.").font(.system(size: 11)).opacity(0.6)
                    }
                }
                Button("Afficher le dossier des vidéos") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.importer.paths.videos])
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(24)
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<LumenCore.Settings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.library.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        ))
        .toggleStyle(.switch)
        .font(.system(size: 12))
    }
}
