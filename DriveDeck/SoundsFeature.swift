import SwiftUI
import UIKit
import AVFoundation
import AppIntents
import UniformTypeIdentifiers

@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()

    @Published var connectSound = "connect.wav"
    @Published var disconnectSound = "disconnect.wav"
    @Published var arriveSound = "arrive.wav"
    @Published var customSounds: [String] = []
    @Published var message: String?

    private var lastRouteDescription = ""
    private var wasCarConnected = false
    private var activePlayers: [String: AVAudioPlayer] = [:]

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        connectSound = UserDefaults.standard.string(forKey: "sound.connect") ?? "connect.wav"
        disconnectSound = UserDefaults.standard.string(forKey: "sound.disconnect") ?? "disconnect.wav"
        arriveSound = UserDefaults.standard.string(forKey: "sound.arrive") ?? "arrive.wav"
        refreshCustomSounds()
    }

    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func routeChanged(_ notification: Notification) {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
        let description = outputs.joined(separator: ",")
        let connected = outputs.contains { $0.contains("CarPlay") || $0.contains("AirPlay") || $0.contains("HDMI") || $0.contains("DisplayPort") }

        Task { @MainActor in
            if lastRouteDescription.isEmpty {
                lastRouteDescription = description
                wasCarConnected = connected
                return
            }
            if lastRouteDescription != description {
                if connected && !wasCarConnected { play(name: connectSound) }
                if !connected && wasCarConnected { play(name: disconnectSound) }
            }
            lastRouteDescription = description
            wasCarConnected = connected
        }
    }

    func installDefaultSoundsIfNeeded() {
        let defaults: [(String, Double, Double)] = [
            ("connect.wav", 660, 0.35),
            ("disconnect.wav", 330, 0.35),
            ("arrive.wav", 880, 0.5)
        ]
        for (name, frequency, duration) in defaults {
            let url = documents.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? toneData(frequency: frequency, duration: duration).write(to: url)
            }
        }
        refreshCustomSounds()
    }

    func refreshCustomSounds() {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        customSounds = all.filter { $0.hasSuffix(".wav") || $0.hasSuffix(".m4a") || $0.hasSuffix(".mp3") }.sorted()
    }

    func importSound(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = documents.appendingPathComponent("custom_\(UUID().uuidString).\(url.pathExtension)")
        if let data = try? Data(contentsOf: url) {
            try? data.write(to: destination)
            refreshCustomSounds()
            message = "Sonido importado: \(url.lastPathComponent)"
        }
    }

    func set(_ slot: SoundSlot, to name: String) {
        switch slot {
        case .connect:
            connectSound = name
            UserDefaults.standard.set(name, forKey: "sound.connect")
        case .disconnect:
            disconnectSound = name
            UserDefaults.standard.set(name, forKey: "sound.disconnect")
        case .arrive:
            arriveSound = name
            UserDefaults.standard.set(name, forKey: "sound.arrive")
        }
    }

    func name(for slot: SoundSlot) -> String {
        switch slot {
        case .connect: return connectSound
        case .disconnect: return disconnectSound
        case .arrive: return arriveSound
        }
    }

    func play(slot: SoundSlot) {
        play(name: name(for: slot))
    }

    func play(name: String) {
        let url = documents.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.prepareToPlay()
            activePlayers[name] = player
            player.play()
        } catch {
            message = "No se pudo reproducir \(name)"
        }
    }

    func announceArrival() {
        play(name: arriveSound)
    }

    private func toneData(frequency: Double, duration: Double) -> Data {
        let sampleRate = 44_100
        let frameCount = Int(Double(sampleRate) * duration)
        var data = Data()

        func appendInt32(_ value: Int) {
            var little = Int32(value).littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        func appendInt16(_ value: Int) {
            let clamped = max(-32_767, min(32_767, value))
            var little = Int16(clamped).littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        data.append(contentsOf: Array("RIFF".utf8))
        appendInt32(36 + frameCount * 2)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendInt32(16)
        appendInt16(1)
        appendInt16(1)
        appendInt32(sampleRate)
        appendInt32(sampleRate * 2)
        appendInt16(2)
        appendInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendInt32(frameCount * 2)

        for index in 0..<frameCount {
            let time = Double(index) / Double(sampleRate)
            let attack = min(1.0, Double(index) / Double(sampleRate) / 0.02)
            let release = min(1.0, Double(frameCount - index) / Double(sampleRate) / 0.06)
            let envelope = max(0, min(attack, release))
            let sample = Int(sin(2 * Double.pi * frequency * time) * 0.35 * envelope * 32_767)
            appendInt16(sample)
        }
        return data
    }
}

enum SoundSlot: String, CaseIterable, Identifiable {
    case connect = "Al conectar"
    case disconnect = "Al desconectar"
    case arrive = "Al llegar"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .connect: return "plug"
        case .disconnect: return "plug.slash"
        case .arrive: return "mappin.and.ellipse"
        }
    }
}

// MARK: - App Intents para Atajos

struct PlayConnectSoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Sonido al conectar"
    static let description: IntentDescription? = IntentDescription("Reproduce el sonido de conexión de DriveDeck.")

    func perform() async throws -> some IntentResult {
        await SoundManager.shared.play(slot: .connect)
        return .result()
    }
}

struct PlayDisconnectSoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Sonido al desconectar"
    static let description: IntentDescription? = IntentDescription("Reproduce el sonido de desconexión de DriveDeck.")

    func perform() async throws -> some IntentResult {
        await SoundManager.shared.play(slot: .disconnect)
        return .result()
    }
}

struct PlayArriveSoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Sonido al llegar"
    static let description: IntentDescription? = IntentDescription("Reproduce el sonido de llegada de DriveDeck.")

    func perform() async throws -> some IntentResult {
        await SoundManager.shared.announceArrival()
        return .result()
    }
}

struct DriveDeckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayConnectSoundIntent(),
            phrases: ["Reproducir sonido de conexión en \(.applicationName)"]
        )
        AppShortcut(
            intent: PlayDisconnectSoundIntent(),
            phrases: ["Reproducir sonido de desconexión en \(.applicationName)"]
        )
        AppShortcut(
            intent: PlayArriveSoundIntent(),
            phrases: ["Reproducir sonido de llegada en \(.applicationName)"]
        )
    }
}

// MARK: - Pantalla Sonidos

struct SoundsView: View {
    @EnvironmentObject private var sounds: SoundManager
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section("Automatizaciones") {
                    ForEach(SoundSlot.allCases) { slot in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: slot.icon).foregroundStyle(.accent)
                                Text(slot.rawValue).font(.headline)
                                Spacer()
                                Button("Probar") { sounds.play(slot: slot) }
                                    .buttonStyle(.bordered)
                            }
                            Picker("Sonido", selection: Binding(
                                get: { sounds.name(for: slot) },
                                set: { sounds.set(slot, to: $0) }
                            )) {
                                ForEach(sounds.customSounds, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Personalizar") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Importar sonido desde Archivos", systemImage: "folder.badge.plus")
                    }
                    Text("También puedes crear automatizaciones en la app Atajos: cuando se conecte CarPlay / llegues a una ubicación, ejecuta «Sonido al conectar» o «Sonido al llegar».")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if let message = sounds.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("CarDash · Sonidos")
            .sheet(isPresented: $showingImporter) {
                DocumentPicker(contentTypes: [.audio], allowsMultiple: false) { urls in
                    if let url = urls.first { sounds.importSound(from: url) }
                    showingImporter = false
                }
            }
        }
    }
}
