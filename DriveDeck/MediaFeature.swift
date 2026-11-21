import SwiftUI
import UIKit
import AVFoundation
import WebKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Modelos

struct Channel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var streamURL: URL
    var group: String?

    init(id: UUID = UUID(), name: String, streamURL: URL, group: String? = nil) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.group = group
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var source: URL
    var channels: [Channel]

    init(id: UUID = UUID(), name: String, source: URL, channels: [Channel]) {
        self.id = id
        self.name = name
        self.source = source
        self.channels = channels
    }
}

struct SavedVideo: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var fileURL: URL

    init(id: UUID = UUID(), name: String, fileURL: URL) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
    }
}

struct WebFavorite: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var url: URL

    init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

enum MediaItem: Identifiable {
    case channel(Channel)
    case video(SavedVideo)
    case website(WebFavorite)

    var id: UUID {
        switch self {
        case .channel(let c): return c.id
        case .video(let v): return v.id
        case .website(let w): return w.id
        }
    }

    var title: String {
        switch self {
        case .channel(let c): return c.name
        case .video(let v): return v.name
        case .website(let w): return w.title
        }
    }

    var url: URL? {
        switch self {
        case .channel(let c): return c.streamURL
        case .video(let v): return v.fileURL
        case .website(let w): return w.url
        }
    }
}

// MARK: - Parser M3U / M3U8

enum M3UParser {
    static func parse(_ text: String, base: URL) -> [Channel] {
        var channels: [Channel] = []
        var pendingName: String?
        var pendingGroup: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                let parts = line.split(separator: ",", maxSplits: 1)
                pendingName = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil
                pendingGroup = attribute("group-title", in: line)
            } else if line.hasPrefix("#") {
                continue
            } else {
                let absolute: URL
                if let direct = URL(string: line), direct.scheme != nil {
                    absolute = direct
                } else {
                    absolute = URL(string: line, relativeTo: base)?.absoluteURL ?? base
                }
                channels.append(Channel(name: pendingName ?? line, streamURL: absolute, group: pendingGroup))
                pendingName = nil
                pendingGroup = nil
            }
        }
        return channels
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(key)=\"([^\"]*)\"") else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}

// MARK: - Store

@MainActor
final class MediaStore: ObservableObject {
    static let shared = MediaStore()

    @Published var playlists: [Playlist] = []
    @Published var localVideos: [SavedVideo] = []
    @Published var favoriteChannels: [Channel] = []
    @Published var webFavorites: [WebFavorite] = []
    @Published var currentItem: MediaItem?
    @Published var player: AVPlayer?
    @Published var browserURL: URL?
    @Published var status: String?

    private let files = FileManager.default
    private var documents: URL {
        files.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        loadAll()
    }

    // MARK: Persistencia

    private func loadAll() {
        playlists = read("playlists.json") ?? []
        localVideos = read("videos.json") ?? []
        favoriteChannels = read("favorites.json") ?? []
        webFavorites = read("websites.json") ?? []
    }

    private func saveAll() {
        write(playlists, "playlists.json")
        write(localVideos, "videos.json")
        write(favoriteChannels, "favorites.json")
        write(webFavorites, "websites.json")
    }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: documents.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: documents.appendingPathComponent(name), options: .atomic)
    }

    // MARK: IPTV

    func addPlaylist(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            status = "Introduce una URL http o https válida."
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                status = "No se pudo leer la lista."
                return
            }
            let channels = M3UParser.parse(text, base: url)
            guard !channels.isEmpty else {
                status = "La lista no contiene canales reproducibles."
                return
            }
            let name = url.lastPathComponent.isEmpty ? "Lista IPTV" : url.lastPathComponent
            playlists.append(Playlist(name: name, source: url, channels: channels))
            saveAll()
            status = "Añadida \(name) · \(channels.count) canales"
        } catch {
            status = "Error al descargar la lista: \(error.localizedDescription)"
        }
    }

    func removePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        favoriteChannels.removeAll { channel in !playlists.contains { $0.channels.contains(channel) } }
        saveAll()
    }

    func reloadPlaylist(_ playlist: Playlist) async {
        await addPlaylist(urlString: playlist.source.absoluteString)
        if playlists.count > 1, let index = playlists.firstIndex(where: { $0.source == playlist.source }) {
            playlists.remove(at: index == 0 ? 1 : 0)
            saveAll()
        }
    }

    // MARK: Vídeos locales

    func importVideos(from urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destination = documents.appendingPathComponent("video_\(UUID().uuidString).\(ext)")
            if files.fileExists(atPath: destination.path) { try? files.removeItem(at: destination) }
            if let data = try? Data(contentsOf: url), (try? data.write(to: destination, options: .atomic)) != nil {
                localVideos.append(SavedVideo(name: url.lastPathComponent, fileURL: destination))
            }
        }
        saveAll()
        if !urls.isEmpty { status = "Importados \(urls.count) vídeo(s)" }
    }

    func removeVideo(_ video: SavedVideo) {
        try? files.removeItem(at: video.fileURL)
        localVideos.removeAll { $0.id == video.id }
        saveAll()
    }

    // MARK: Favoritos y webs

    func toggleFavorite(_ channel: Channel) {
        if let index = favoriteChannels.firstIndex(where: { $0.id == channel.id }) {
            favoriteChannels.remove(at: index)
        } else {
            favoriteChannels.append(channel)
        }
        saveAll()
    }

    func isFavorite(_ channel: Channel) -> Bool {
        favoriteChannels.contains(channel)
    }

    func addWebsite(title: String, urlString: String) {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            status = "Introduce una URL http o https válida."
            return
        }
        webFavorites.append(WebFavorite(title: title.isEmpty ? url.host ?? "Web" : title, url: url))
        saveAll()
    }

    func removeWebsite(_ site: WebFavorite) {
        webFavorites.removeAll { $0.id == site.id }
        saveAll()
    }

    // MARK: Reproducción

    func play(_ item: MediaItem) {
        stop()
        currentItem = item
        guard let url = item.url else { return }

        if case .website = item {
            browserURL = url
            ExternalDisplayManager.shared.currentWebURL = url
            ExternalDisplayManager.shared.currentVideoURL = nil
            ExternalDisplayManager.shared.currentTitle = item.title
            return
        }

        browserURL = nil
        let newPlayer = AVPlayer(url: url)
        newPlayer.allowsExternalPlayback = true
        newPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        player = newPlayer
        newPlayer.play()
        ExternalDisplayManager.shared.currentVideoURL = url
        ExternalDisplayManager.shared.currentWebURL = nil
        ExternalDisplayManager.shared.currentTitle = item.title
    }

    func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func stop() {
        player?.pause()
        player = nil
        currentItem = nil
        browserURL = nil
        ExternalDisplayManager.shared.currentVideoURL = nil
        ExternalDisplayManager.shared.currentWebURL = nil
        ExternalDisplayManager.shared.currentTitle = ""
    }
}

// MARK: - Pantalla externa / AirPlay

@MainActor
final class ExternalDisplayManager: NSObject, ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published var isConnected = false
    @Published var currentTitle = ""
    @Published var currentVideoURL: URL?
    @Published var currentWebURL: URL?

    private var externalWindow: UIWindow?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
        if let screen = UIScreen.screens.dropFirst().first {
            attach(to: screen)
        }
    }

    @objc private func screenDidConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        Task { @MainActor in self.attach(to: screen) }
    }

    @objc private func screenDidDisconnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen,
              externalWindow?.screen === screen else { return }
        Task { @MainActor in
            self.externalWindow?.isHidden = true
            self.externalWindow = nil
            self.isConnected = false
        }
    }

    private func attach(to screen: UIScreen) {
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        let host = UIHostingController(rootView: ExternalDisplayView().environmentObject(self))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        externalWindow = window
        isConnected = true
    }
}

struct ExternalDisplayView: View {
    @EnvironmentObject private var external: ExternalDisplayManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = external.currentWebURL {
                ExternalWebView(url: url)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "car.display")
                        .font(.system(size: 64))
                    Text(external.currentTitle.isEmpty ? "DriveDeck" : external.currentTitle)
                        .font(.largeTitle.bold())
                    Text("Elige el receptor AirPlay desde el botón de duplicado en tu iPhone.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            }
        }
    }
}

struct ExternalWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.allowsBackForwardNavigationGestures = true
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        web.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loaded: URL?
    }
}

// MARK: - UI helpers

struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .label
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct PlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView { WKWebView() }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        web.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loaded: URL?
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.movie]
    var allowsMultiple = true
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - Pantalla Cast

struct CastView: View {
    @EnvironmentObject private var media: MediaStore
    @ObservedObject private var external = ExternalDisplayManager.shared
    @State private var playlistURL = ""
    @State private var showingPlaylistInput = false
    @State private var webTitle = ""
    @State private var webURL = ""
    @State private var showingWebInput = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingFiles = false

    var body: some View {
        NavigationStack {
            List {
                if let item = media.currentItem {
                    Section("Reproduciendo") {
                        HStack {
                            Image(systemName: itemIcon(item)).foregroundStyle(.accent)
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Button {
                                media.togglePlayback()
                            } label: {
                                Image(systemName: media.player?.timeControlStatus == .playing ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                            }
                            Button { media.stop() } label: {
                                Image(systemName: "stop.circle.fill").font(.title2)
                            }
                        }
                        if media.browserURL != nil {
                            WebView(url: media.browserURL!)
                                .frame(height: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if media.player != nil {
                            PlayerContainer(player: media.player!)
                                .frame(height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        HStack {
                            Text("Duplicar / AirPlay").font(.subheadline)
                            Spacer()
                            AirPlayPicker().frame(width: 34, height: 34)
                        }
                    }
                }

                Section("Duplicado de pantalla") {
                    HStack {
                        Image(systemName: externalIcon)
                        VStack(alignment: .leading) {
                            Text("Pantalla externa \(external.isConnected ? "conectada" : "no detectada")")
                            Text("Toca el icono de AirPlay para enviar vídeo o la web a la pantalla del coche.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Listas IPTV") {
                    ForEach(media.playlists) { playlist in
                        NavigationLink(playlist.name) {
                            PlaylistDetailView(playlist: playlist)
                        }
                    }
                    Button {
                        showingPlaylistInput = true
                    } label: {
                        Label("Añadir lista M3U / M3U8", systemImage: "plus")
                    }
                }

                Section("Vídeos locales") {
                    ForEach(media.localVideos) { video in
                        HStack {
                            Button { media.play(.video(video)) } label: {
                                Label(video.name, systemImage: "film")
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) { media.removeVideo(video) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    PhotosPicker(selection: $photoItems, matching: .videos) {
                        Label("Importar desde Fotos", systemImage: "photo.on.rectangle")
                    }
                    Button { showingFiles = true } label: {
                        Label("Importar desde Archivos", systemImage: "folder")
                    }
                }

                Section("Favoritos") {
                    if media.favoriteChannels.isEmpty {
                        Text("Marca canales con la estrella para verlos aquí.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(media.favoriteChannels) { channel in
                            Button { media.play(.channel(channel)) } label: {
                                Label(channel.name, systemImage: "star.fill")
                            }
                        }
                    }
                }

                Section("Webs") {
                    ForEach(media.webFavorites) { site in
                        HStack {
                            Button { media.play(.website(site)) } label: {
                                Label(site.title, systemImage: "globe")
                            }
                            Spacer()
                            Button(role: .destructive) { media.removeWebsite(site) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    Button {
                        showingWebInput = true
                    } label: {
                        Label("Guardar web", systemImage: "plus")
                    }
                }

                if let status = media.status {
                    Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("CarDash · Cast")
            .sheet(isPresented: $showingPlaylistInput) {
                InputSheet(title: "Lista IPTV", placeholder: "https://ejemplo.com/lista.m3u8", text: $playlistURL) {
                    Task { await media.addPlaylist(urlString: playlistURL); playlistURL = "" }
                }
            }
            .sheet(isPresented: $showingWebInput) {
                VStack(spacing: 16) {
                    Text("Guardar web").font(.headline)
                    TextField("Nombre", text: $webTitle).textFieldStyle(.roundedBorder)
                    TextField("https://…", text: $webURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    Button("Guardar") {
                        media.addWebsite(title: webTitle, urlString: webURL)
                        webTitle = ""
                        webURL = ""
                        showingWebInput = false
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancelar", role: .cancel) { showingWebInput = false }
                }
                .padding()
            }
            .sheet(isPresented: $showingFiles) {
                DocumentPicker { urls in
                    media.importVideos(from: urls)
                    showingFiles = false
                }
            }
            .onChange(of: photoItems) { _, items in
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
                        photoItems = []
                    }
                }
            }
        }
    }

    private var externalIcon: String {
        external.isConnected ? "tv.fill" : "tv"
    }

    private func itemIcon(_ item: MediaItem) -> String {
        switch item {
        case .channel: return "broadcast"
        case .video: return "film"
        case .website: return "globe"
        }
    }
}

struct InputSheet: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            HStack {
                Button("Cancelar", role: .cancel) { text = "" }
                Button("Añadir", action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var media: MediaStore
    let playlist: Playlist
    @State private var query = ""

    private var filtered: [Channel] {
        query.isEmpty ? playlist.channels : playlist.channels.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.group ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Buscar canal o grupo", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            Section("\(filtered.count) canales") {
                ForEach(filtered) { channel in
                    HStack {
                        Button { media.play(.channel(channel)) } label: {
                            VStack(alignment: .leading) {
                                Text(channel.name).lineLimit(1)
                                if let group = channel.group {
                                    Text(group).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button { media.toggleFavorite(channel) } label: {
                            Image(systemName: media.isFavorite(channel) ? "star.fill" : "star")
                                .foregroundStyle(media.isFavorite(channel) ? .yellow : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            Button("Recargar") {
                Task { await media.reloadPlaylist(playlist) }
            }
        }
    }
}
