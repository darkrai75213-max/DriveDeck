import SwiftUI
import UIKit
import AVFoundation
import UserNotifications

@main
struct DriveDeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var media = MediaStore.shared
    @StateObject private var trips = TripStore.shared
    @StateObject private var sounds = SoundManager.shared
    @AppStorage("drivedeck.accent") private var accentRaw: String = "blue"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(media)
                .environmentObject(trips)
                .environmentObject(sounds)
                .tint(AppAccent(rawValue: accentRaw)?.color ?? .blue)
                .onAppear {
                    sounds.configureSession()
                    sounds.installDefaultSoundsIfNeeded()
                    _ = ExternalDisplayManager.shared
                    if TripStore.shared.autoDetect { TripStore.shared.startMonitoringIfNeeded() }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case blue, orange, green, purple, red

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .red: return .red
        }
    }

    var label: String {
        switch self {
        case .blue: return "Azul"
        case .orange: return "Naranja"
        case .green: return "Verde"
        case .purple: return "Morado"
        case .red: return "Rojo"
        }
    }
}

struct ContentView: View {
    @StateObject private var vehicles = VehicleStore.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TransmitView()
                .tabItem { Label("transmitir", systemImage: "tv") }
                .tag(0)
            TripView()
                .tabItem { Label("recorrido", systemImage: "map.fill") }
                .tag(1)
            WidgetsGuideView()
                .tabItem { Label("widgets", systemImage: "square.grid.2x2") }
                .tag(2)
            SoundsView()
                .tabItem { Label("sonidos", systemImage: "speaker.wave.2") }
                .tag(3)
            ProfileView()
                .tabItem { Label("perfil", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .environmentObject(vehicles)
        .fullScreenCover(isPresented: Binding(
            get: { vehicles.needsSetup },
            set: { _ in }
        )) {
            GarageSetupView()
                .environmentObject(vehicles)
        }
    }
}

struct SettingsView: View {
    @AppStorage("drivedeck.accent") private var accentRaw: String = "blue"
    @EnvironmentObject private var vehicles: VehicleStore
    @State private var showingGarage = false

    var body: some View {
        NavigationStack {
            List {
                Section("Garaje") {
                    Button {
                        showingGarage = true
                    } label: {
                        HStack {
                            Image(systemName: vehicles.vehicle?.design.icon ?? "car.fill")
                            Text(vehicles.vehicle?.nickname ?? "Elegir vehículo")
                            Spacer()
                            Text(vehicles.vehicle?.design.title ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Apariencia") {
                    Picker("Color", selection: $accentRaw) {
                        ForEach(AppAccent.allCases) { item in
                            Text(item.label).tag(item.rawValue)
                        }
                    }
                }
                Section("Acerca de") {
                    Text("DriveDeck · funcionalidad equivalente a CarDash v1.3.2, sin compras ni suscripciones.")
                    Text("Todo se guarda en este iPhone. No hay analítica ni servidores propios.")
                }
                Section("Safety") {
                    Text("El vídeo está pensado para verlo con el coche aparcado. El conductor debe mantener la atención en la vía.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $showingGarage) {
                GarageSetupView(vehicle: vehicles.vehicle)
                    .environmentObject(vehicles)
            }
        }
    }
}
