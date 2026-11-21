import SwiftUI
import PhotosUI

struct Achievement: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

struct ProfileView: View {
    @EnvironmentObject private var vehicles: VehicleStore
    @EnvironmentObject private var trips: TripStore
    @AppStorage("drivedeck.accent") private var accentRaw: String = "red"

    @State private var showingGarage = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profilePhoto: UIImage?
    @State private var showingAchievements = false

    private let achievements: [Achievement] = [
        Achievement(title: "Primer viaje", icon: "car.fill"),
        Achievement(title: "10 viajes", icon: "road.lanes"),
        Achievement(title: "25 viajes", icon: "number.circle.fill"),
        Achievement(title: "50 viajes", icon: "medal.fill"),
        Achievement(title: "100 viajes", icon: "trophy.fill"),
        Achievement(title: "100 km", icon: "100.circle.fill"),
        Achievement(title: "500 km", icon: "500.circle.fill"),
        Achievement(title: "1.000 km", icon: "1.circle.fill"),
        Achievement(title: "5.000 km", icon: "5.circle.fill"),
        Achievement(title: "10.000 km", icon: "10.circle.fill"),
        Achievement(title: "Viaje de 50 km", icon: "location.fill"),
        Achievement(title: "Viaje de 100 km", icon: "map.fill"),
        Achievement(title: "Conducción suave", icon: "leaf.fill"),
        Achievement(title: "Sin frenazos", icon: "arrow.down.right.circle.fill"),
        Achievement(title: "Sin curvas bruscas", icon: "arrow.turn.up.right"),
        Achievement(title: "Puntuación 100", icon: "star.fill")
    ]

    private var vehicle: Vehicle? { vehicles.vehicle }
    private var accent: Color { AppAccent(rawValue: accentRaw)?.color ?? .red }

    var body: some View {
        NavigationStack {
            ZStack {
                CockpitBackground(accent: accent)
                ScrollView {
                    VStack(spacing: 18) {
                        if let vehicle {
                            HStack(spacing: 14) {
                                ZStack {
                                    if let photo = profilePhoto {
                                        Image(uiImage: photo)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image("seat-ibiza-40-aniversario")
                                            .resizable()
                                            .scaledToFill()
                                    }
                                }
                                .frame(width: 104, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18)))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vehicle.brandModel.isEmpty ? "SEAT Ibiza" : vehicle.brandModel)
                                        .font(.title3.bold())
                                    Text(vehicle.nickname)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        Label("Cambiar foto", systemImage: "photo.on.rectangle")
                                            .font(.caption.bold())
                                    }
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }

                        HStack(spacing: 12) {
                            ProfileStat(title: "KM totales", value: trips.distanceText(trips.totalDistance), icon: "road.lanes")
                            ProfileStat(title: "Viajes", value: "\(trips.trips.count)", icon: "map.fill")
                            ProfileStat(title: "Logros", value: "0/\(achievements.count)", icon: "trophy.fill")
                        }

                        Button {
                            showingAchievements = true
                        } label: {
                            Label("Ver logros (0/\(achievements.count))", systemImage: "trophy")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("CONFIGURACIÓN")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Toggle("Detección automática de recorridos", isOn: Binding(
                                get: { trips.autoDetect },
                                set: { trips.setAutoDetect($0) }
                            ))
                            Toggle("Siempre km/h", isOn: Binding(
                                get: { trips.useKilometers },
                                set: { trips.setUseKilometers($0) }
                            ))
                            Picker("Color del tema", selection: $accentRaw) {
                                ForEach(AppAccent.allCases) { item in
                                    Text(item.label).tag(item.rawValue)
                                }
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))

                        Button {
                            showingGarage = true
                        } label: {
                            Label("Editar vehículo (SEAT Ibiza)", systemImage: "car.sport.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(accent, in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.white)
                        }

                        Text("Tus datos se guardan solo en este iPhone. Sin compras ni suscripciones.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("perfil")
            .sheet(isPresented: $showingGarage) {
                GarageSetupView(vehicle: vehicles.vehicle)
                    .environmentObject(vehicles)
            }
            .sheet(isPresented: $showingAchievements) {
                NavigationStack {
                    List {
                        Section("Logros desbloqueables") {
                            ForEach(achievements) { item in
                                HStack {
                                    Image(systemName: item.icon).foregroundStyle(.secondary)
                                    Text(item.title)
                                    Spacer()
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .navigationTitle("Logros · 0/\(achievements.count)")
                    .toolbar { Button("Cerrar") { showingAchievements = false } }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await MainActor.run { profilePhoto = UIImage(data: data) }
                }
            }
        }
    }
}

struct ProfileStat: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.red)
            Text(value)
                .font(.subheadline.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
