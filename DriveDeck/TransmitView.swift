import SwiftUI
import PhotosUI

struct TransmitView: View {
    @EnvironmentObject private var media: MediaStore

    private let sections: [(String, String, String)] = [
        ("fuente multimedia", "Selecciona canales IPTV y reproduce tu contenido", "broadcast"),
        ("videos locales", "Importa vídeos desde Fotos o Archivos y reprodúcelos", "film.stack.fill"),
        ("duplicar iphone", "Envía la pantalla o el vídeo por AirPlay", "airplayvideo"),
        ("navegador", "Abre webs y páginas de vídeo en el coche", "globe")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                CockpitBackground(accent: .red)
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transmitir")
                                .font(.title2.bold())
                            Text("Todo el contenido disponible en DriveDeck, organizado igual que en CarDash.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Contenido") {
                        ForEach(sections, id: \.0) { title, subtitle, icon in
                            NavigationLink {
                                TransmitDetailView(title: title, subtitle: subtitle, icon: icon)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title)
                                            .font(.subheadline.bold())
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if let status = media.status {
                        Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("transmitir")
        }
    }
}

struct TransmitDetailView: View {
    @EnvironmentObject private var media: MediaStore
    @ObservedObject private var external = ExternalDisplayManager.shared

    let title: String
    let subtitle: String
    let icon: String

    @State private var playlistURL = ""
    @State private var webTitle = ""
    @State private var webURL = ""
    @State private var showingFiles = false
    @State private var photoVideos: [PhotosPickerItem] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(subtitle, systemImage: icon)
                        .font(.subheadline)
                    Text("El vídeo está pensado para verlo con el coche aparcado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let item = media.currentItem {
                Section("Reproduciendo") {
                    HStack {
                        Text(item.title).lineLimit(1)
                        Spacer()
                        Button {
                            media.togglePlayback()
                        } label: {
                            Image(systemName: media.player?.timeControlStatus == .playing ? "pause.circle.fill" : "play.circle.fill")
                        }
                        Button {
                            media.stop()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                        }
                    }
                    if let url = media.browserURL {
                        WebView(url: url).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let player = media.player {
                        PlayerContainer(player: player).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            switch title {
            case "fuente multimedia":
                Section("Listas IPTV") {
                    ForEach(media.playlists) { playlist in
                        NavigationLink(playlist.name) { PlaylistDetailView(playlist: playlist) }
                    }
                    TextField("https://ejemplo.com/lista.m3u8", text: $playlistURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    Button("Añadir lista M3U / M3U8") {
                        Task { await media.addPlaylist(urlString: playlistURL); playlistURL = "" }
                    }
                }
                Section("Favoritos") {
                    if media.favoriteChannels.isEmpty {
                        Text("Marca canales con la estrella para verlos aquí.").foregroundStyle(.secondary)
                    } else {
                        ForEach(media.favoriteChannels) { channel in
                            Button {
                                media.play(.channel(channel))
                            } label: {
                                Label(channel.name, systemImage: "star.fill")
                            }
                        }
                    }
                }

            case "videos locales":
                Section("Vídeos guardados") {
                    ForEach(media.localVideos) { video in
                        HStack {
                            Button {
                                media.play(.video(video))
                            } label: {
                                Label(video.name, systemImage: "film")
                            }
                            Spacer()
                            Button(role: .destructive) {
                                media.removeVideo(video)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    PhotosPicker(selection: $photoVideos, matching: .videos) {
                        Label("Importar desde Fotos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingFiles = true
                    } label: {
                        Label("Importar desde Archivos", systemImage: "folder")
                    }
                }

            case "duplicar iphone":
                Section("AirPlay / pantalla externa") {
                    HStack {
                        Image(systemName: external.isConnected ? "tv.fill" : "tv")
                        VStack(alignment: .leading) {
                            Text("Pantalla externa \(external.isConnected ? "conectada" : "no detectada")")
                            Text("Toca el icono de AirPlay para elegir la pantalla del coche.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    AirPlayPicker().frame(width: 44, height: 44)
                    Text("Para duplicar toda la pantalla usa también Centro de control → Duplicación de pantalla.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

            case "navegador":
                Section("Webs guardadas") {
                    ForEach(media.webFavorites) { site in
                        HStack {
                            Button {
                                media.play(.website(site))
                            } label: {
                                Label(site.title, systemImage: "globe")
                            }
                            Spacer()
                            Button(role: .destructive) {
                                media.removeWebsite(site)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    TextField("Nombre", text: $webTitle).textFieldStyle(.roundedBorder)
                    TextField("https://…", text: $webURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    Button("Guardar y abrir") {
                        media.addWebsite(title: webTitle, urlString: webURL)
                        webTitle = ""; webURL = ""
                    }
                }

            default:
                EmptyView()
            }
        }
        .navigationTitle(title)
        .sheet(isPresented: $showingFiles) {
            DocumentPicker { urls in
                media.importVideos(from: urls)
                showingFiles = false
            }
        }
        .onChange(of: photoVideos) { _, items in
            Task {
                var urls: [URL] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + "." + ext)
                        if (try? data.write(to: temp)) != nil { urls.append(temp) }
                    }
                }
                await MainActor.run {
                    media.importVideos(from: urls)
                    photoVideos = []
                }
            }
        }
    }
}
