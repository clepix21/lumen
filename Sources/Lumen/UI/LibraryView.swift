import AppKit
import LumenCore
import SwiftUI
import UniformTypeIdentifiers

/// "Bibliothèque" section: hero with the current wallpaper, then "Mes vidéos" and "Playlists" rows.
struct LibraryView: View {
    @ObservedObject var model: AppModel
    // Plain `State` values: the `@State` macro plugin is not available without Xcode.
    private let renaming = State<Video?>(initialValue: nil)
    private let renameText = State(initialValue: "")
    private let deleting = State<Video?>(initialValue: nil)

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                section("Mes vidéos") {
                    AddTile(action: pickVideos)
                    ForEach(model.library.videos) { video in
                        videoTile(video)
                    }
                }
                section("Playlists") {
                    ForEach(model.library.playlists) { playlist in
                        playlistTile(playlist)
                    }
                    AddTile { model.createPlaylist(name: "Nouvelle playlist") }
                }
            }
        }
        .alert("Renommer la vidéo", isPresented: Binding(
            get: { renaming.wrappedValue != nil },
            set: { if !$0 { renaming.wrappedValue = nil } }
        )) {
            TextField("Nom", text: renameText.projectedValue)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                let name = renameText.wrappedValue.trimmingCharacters(in: .whitespaces)
                if let video = renaming.wrappedValue, !name.isEmpty {
                    model.renameVideo(id: video.id, to: name)
                }
            }
        }
        .confirmationDialog(
            "Supprimer « \(deleting.wrappedValue?.name ?? "") » ?",
            isPresented: Binding(get: { deleting.wrappedValue != nil }, set: { if !$0 { deleting.wrappedValue = nil } })
        ) {
            Button("Supprimer", role: .destructive) {
                if let video = deleting.wrappedValue { model.deleteVideo(id: video.id) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La copie de la vidéo dans Lumen sera supprimée. Le fichier d'origine n'est pas touché.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.04)
                .overlay {
                    if let id = model.currentVideoID, let image = ThumbnailCache.image(at: model.thumbnailURL(for: id)) {
                        Image(nsImage: image).resizable().scaledToFill()
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                if let video = model.currentVideo {
                    Text(DisplayText.heroCaption(playlistName: model.currentPlaylist?.name))
                        .font(.system(size: 10, weight: .medium)).tracking(0.8).opacity(0.7)
                    Text(video.name).font(.system(size: 30, weight: .semibold))
                    Text(DisplayText.summary(for: video)).font(.system(size: 11)).opacity(0.7).padding(.bottom, 8)
                    HStack(spacing: 6) {
                        PillButton(title: model.userPaused ? "Lecture" : "Pause",
                                   systemImage: model.userPaused ? "play.fill" : "pause.fill",
                                   prominent: true) { model.togglePause() }
                        PillButton(title: model.library.settings.isMuted ? "Son coupé" : "Son activé",
                                   systemImage: model.library.settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                            model.toggleMute()
                        }
                        PillButton(title: "Suivante", systemImage: "forward.fill", isEnabled: model.isInPlaylist) {
                            model.next()
                        }
                    }
                } else {
                    Text("Aucune vidéo en fond d'écran").font(.system(size: 26, weight: .semibold))
                    Text("Ajoute une vidéo de ton Mac pour commencer, ou glisse-la dans cette fenêtre.")
                        .font(.system(size: 12)).opacity(0.7).padding(.bottom, 8)
                    PillButton(title: "Ajouter une vidéo", systemImage: "plus", prominent: true, action: pickVideos)
                }
            }
            .padding(24)
        }
        .frame(height: 320)
        .clipped()
    }

    // MARK: - Rows

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 14, weight: .semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12, content: content)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func videoTile(_ video: Video) -> some View {
        Button {
            model.play(videoID: video.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ThumbnailTile(url: model.thumbnailURL(for: video.id), isCurrent: model.currentVideoID == video.id)
                Text(video.name).font(.system(size: 11)).lineLimit(1).opacity(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Renommer…") {
                renameText.wrappedValue = video.name
                renaming.wrappedValue = video
            }
            Menu("Ajouter à une playlist") {
                ForEach(model.library.playlists) { playlist in
                    Button(playlist.name) { model.addVideo(video.id, toPlaylist: playlist.id) }
                }
                Divider()
                Button("Créer une playlist…") {
                    let id = model.createPlaylist(name: "Nouvelle playlist")
                    model.addVideo(video.id, toPlaylist: id)
                }
            }
            Divider()
            Button("Supprimer…", role: .destructive) { deleting.wrappedValue = video }
        }
    }

    private func playlistTile(_ playlist: Playlist) -> some View {
        Button {
            model.play(playlistID: playlist.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ThumbnailTile(url: playlist.videoIDs.first.map(model.thumbnailURL(for:)),
                              isCurrent: model.library.selection == .playlist(playlist.id))
                Text("\(playlist.name) · \(playlist.videoIDs.count)").font(.system(size: 11)).lineLimit(1).opacity(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Supprimer la playlist", role: .destructive) { model.deletePlaylist(id: playlist.id) }
        }
    }

    private func pickVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await model.importVideos(urls) }
    }
}
