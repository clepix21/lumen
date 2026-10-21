import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case library = "Bibliothèque"
    case playlists = "Playlists"
    case settings = "Réglages"

    var id: Self { self }
}

/// Main window: dark background, a floating pill switching between the three sections.
struct MainWindowView: View {
    @ObservedObject var model: AppModel
    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode,
    // so view state is declared as plain `State` values instead.
    private let section = State(initialValue: MainSection.library)

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch section.wrappedValue {
                case .library:
                    LibraryView(model: model)
                case .playlists:
                    PlaylistsView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pill.padding(.top, 10)

            if let progress = model.importProgress {
                VStack(spacing: 6) {
                    Text("Import en cours…").font(.system(size: 12, weight: .medium))
                    ProgressView(value: progress).frame(width: 220)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 760, minHeight: 560)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importVideos(urls) }
            return !urls.isEmpty
        }
        .alert("Lumen", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var pill: some View {
        HStack(spacing: 2) {
            ForEach(MainSection.allCases) { item in
                Button {
                    section.wrappedValue = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(section.wrappedValue == item ? Color.white.opacity(0.2) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
