import LumenCore
import SwiftUI

/// "Playlists" section: playlists on the left, the selected playlist's ordered videos on the right.
struct PlaylistsView: View {
    @ObservedObject var model: AppModel
    // Plain `State` values: the `@State` macro plugin is not available without Xcode.
    private let selectedID = State<UUID?>(initialValue: nil)
    private let renaming = State<Playlist?>(initialValue: nil)
    private let renameText = State(initialValue: "")

    private var selected: Playlist? {
        selectedID.wrappedValue.flatMap { model.library.playlist(id: $0) } ?? model.library.playlists.first
    }

    var body: some View {
        HStack(spacing: 0) {
            playlistList
                .frame(width: 220)
                .background(Color.white.opacity(0.03))
            Divider()
            if let playlist = selected {
                PlaylistDetail(model: model, playlist: playlist)
            } else {
                Text("Crée une playlist pour enchaîner plusieurs vidéos.")
                    .opacity(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 52)
        .alert("Renommer la playlist", isPresented: Binding(
            get: { renaming.wrappedValue != nil },
            set: { if !$0 { renaming.wrappedValue = nil } }
        )) {
            TextField("Nom", text: renameText.projectedValue)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                let name = renameText.wrappedValue.trimmingCharacters(in: .whitespaces)
                if let playlist = renaming.wrappedValue, !name.isEmpty {
                    model.renamePlaylist(id: playlist.id, to: name)
                }
            }
        }
    }

    private var playlistList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.library.playlists) { playlist in
                        Button {
                            selectedID.wrappedValue = playlist.id
                        } label: {
                            HStack {
                                Image(systemName: model.library.selection == .playlist(playlist.id) ? "play.fill" : "music.note.list")
                                    .frame(width: 16)
                                Text(playlist.name).lineLimit(1)
                                Spacer()
                                Text("\(playlist.videoIDs.count)").opacity(0.5)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected?.id == playlist.id ? Color.white.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Renommer…") {
                                renameText.wrappedValue = playlist.name
                                renaming.wrappedValue = playlist
                            }
                            Button("Supprimer", role: .destructive) { model.deletePlaylist(id: playlist.id) }
                        }
                    }
                }
                .padding(8)
            }
            Button {
                selectedID.wrappedValue = model.createPlaylist(name: "Nouvelle playlist")
            } label: {
                Label("Nouvelle playlist", systemImage: "plus").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .opacity(0.7)
            .padding(12)
        }
    }
}

/// Ordered videos of one playlist, with drag reordering, removal and adding from the library.
private struct PlaylistDetail: View {
    @ObservedObject var model: AppModel
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(playlist.name).font(.system(size: 20, weight: .semibold))
                Spacer()
                Menu {
                    let available = model.library.videos.filter { !playlist.videoIDs.contains($0.id) }
                    if available.isEmpty {
                        Text("Toutes tes vidéos sont déjà dans cette playlist")
                    }
                    ForEach(available) { video in
                        Button(video.name) { model.addVideo(video.id, toPlaylist: playlist.id) }
                    }
                } label: {
                    Label("Ajouter des vidéos", systemImage: "plus")
                }
                .fixedSize()
                PillButton(title: "Lancer", systemImage: "play.fill", prominent: true,
                           isEnabled: !playlist.videoIDs.isEmpty) {
                    model.play(playlistID: playlist.id)
                }
            }

            List {
                ForEach(playlist.videoIDs, id: \.self) { id in
                    if let video = model.library.video(id: id) {
                        HStack(spacing: 10) {
                            ThumbnailTile(url: model.thumbnailURL(for: id), isCurrent: model.currentVideoID == id)
                                .frame(width: 80)
                            VStack(alignment: .leading) {
                                Text(video.name).font(.system(size: 12, weight: .medium))
                                Text(DisplayText.summary(for: video)).font(.system(size: 10)).opacity(0.6)
                            }
                            Spacer()
                            Button {
                                model.removeVideo(id, fromPlaylist: playlist.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Retirer de la playlist")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onMove { source, destination in
                    model.moveVideos(inPlaylist: playlist.id, fromOffsets: source, toOffset: destination)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(20)
    }
}
