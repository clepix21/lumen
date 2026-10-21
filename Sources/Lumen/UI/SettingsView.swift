import AppKit
import LumenCore
import SwiftUI

/// "Réglages" section.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    // Plain `State` values: the `@State` macro plugin is not available without Xcode.
    private let cacheSize = State<Int64>(initialValue: 0)
    private let confirmingClear = State(initialValue: false)

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
                group("Écrans") {
                    Toggle("Même vidéo sur tous les écrans", isOn: Binding(
                        get: { model.library.screenLayout.sameOnAllScreens },
                        set: { model.setSameOnAllScreens($0) }
                    ))
                    .toggleStyle(.switch)
                    .font(.system(size: 12))
                    Text(model.screenChoices.count > 1
                         ? "Désactivé, choisis l'écran au-dessus de « Mes vidéos » avant de cliquer sur une vidéo."
                         : "Un seul écran est branché pour le moment.")
                        .font(.system(size: 11)).opacity(0.6)
                }
                group("Système") {
                    toggle("Lancer au démarrage du Mac", \.launchAtLogin)
                    toggle("Raccourcis clavier globaux", \.globalShortcuts)
                    Text("⌃⌥⌘P pause ou lecture · ⌃⌥⌘→ vidéo suivante · ⌃⌥⌘← vidéo précédente · ⌃⌥⌘S son")
                        .font(.system(size: 11)).opacity(0.6)
                    toggle("Vérifier les mises à jour", \.checkForUpdates)
                    if let update = model.availableUpdate {
                        Button("Télécharger la version \(update.version)") {
                            NSWorkspace.shared.open(update.pageURL)
                        }
                    } else {
                        Text("Version \(AppModel.appVersion). Lumen consulte GitHub une fois par jour, sans envoyer de données.")
                            .font(.system(size: 11)).opacity(0.6)
                    }
                    if #available(macOS 26, *) {
                        toggle("Écran de verrouillage animé", \.lockScreenEnabled)
                        Text("La vidéo du bureau s'affiche aussi sur l'écran de verrouillage, sans le son.")
                            .font(.system(size: 11)).opacity(0.6)
                    } else {
                        Toggle("Écran de verrouillage animé", isOn: .constant(false)).disabled(true)
                        Text("Nécessite macOS 26 ou plus récent.").font(.system(size: 11)).opacity(0.6)
                    }
                }
                group("Stockage") {
                    HStack {
                        Text("Cache : \(DisplayText.size(cacheSize.wrappedValue))")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Vider le cache") { confirmingClear.wrappedValue = true }
                            .disabled(cacheSize.wrappedValue == 0)
                    }
                    Text("Supprime les versions préparées pour l'écran de verrouillage et les fichiers inutilisés. Tes vidéos ne sont pas touchées.")
                        .font(.system(size: 11)).opacity(0.6)
                    Button("Afficher le dossier des vidéos") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.importer.paths.videos])
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(24)
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        }
        .onAppear { cacheSize.wrappedValue = model.cacheSize() }
        .confirmationDialog(
            "Vider le cache (\(DisplayText.size(cacheSize.wrappedValue))) ?",
            isPresented: confirmingClear.projectedValue
        ) {
            Button("Vider le cache", role: .destructive) {
                model.clearCache()
                cacheSize.wrappedValue = model.cacheSize()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les versions pour l'écran de verrouillage seront recréées si besoin.")
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
