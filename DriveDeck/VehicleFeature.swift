import SwiftUI
import UIKit

// MARK: - Modelo de vehículo

enum VehicleDesign: String, Codable, CaseIterable, Identifiable {
    case neutral, sport, luxury, electric, suv, classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutral: return "Neutro"
        case .sport: return "Deportivo"
        case .luxury: return "Lujo"
        case .electric: return "Eléctrico"
        case .suv: return "Todo terreno"
        case .classic: return "Clásico"
        }
    }

    var tagline: String {
        switch self {
        case .neutral: return "Uso diario"
        case .sport: return "Alta gama"
        case .luxury: return "Premium"
        case .electric: return "Cero emisiones"
        case .suv: return "Cualquier ruta"
        case .classic: return "Estilo atemporal"
        }
    }

    var icon: String {
        switch self {
        case .neutral: return "car.fill"
        case .sport: return "car.sport.fill"
        case .luxury: return "crown.fill"
        case .electric: return "bolt.car.fill"
        case .suv: return "car.fill"
        case .classic: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .neutral: return .blue
        case .sport: return .red
        case .luxury: return .purple
        case .electric: return .green
        case .suv: return .orange
        case .classic: return .brown
        }
    }
}

struct Vehicle: Codable, Identifiable, Hashable {
    let id: UUID
    var nickname: String
    var brandModel: String
    var plate: String
    var design: VehicleDesign
    var accentRaw: String

    init(
        id: UUID = UUID(),
        nickname: String,
        brandModel: String,
        plate: String,
        design: VehicleDesign,
        accentRaw: String
    ) {
        self.id = id
        self.nickname = nickname
        self.brandModel = brandModel
        self.plate = plate
        self.design = design
        self.accentRaw = accentRaw
    }

    var accent: Color {
        AppAccent(rawValue: accentRaw)?.color ?? design.color
    }
}

@MainActor
final class VehicleStore: ObservableObject {
    static let shared = VehicleStore()

    @Published var vehicle: Vehicle? {
        didSet { persist() }
    }

    static let ibiza = Vehicle(
        nickname: "Mi Ibiza",
        brandModel: "SEAT Ibiza",
        plate: "",
        design: .sport,
        accentRaw: "red"
    )

    private let key = "drivedeck.vehicle"

    init() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            vehicle = Self.ibiza
            return
        }
        vehicle = (try? JSONDecoder().decode(Vehicle.self, from: data)) ?? Self.ibiza
    }

    var needsSetup: Bool { vehicle == nil }

    func save(_ vehicle: Vehicle) {
        self.vehicle = vehicle
    }

    private func persist() {
        guard let vehicle else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(vehicle) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Componentes de estética "cockpit"

struct CockpitBackground: View {
    var accent: Color = .blue

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [accent.opacity(0.22), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }
}

struct CockpitCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

struct SpeedRing: View {
    let speed: Double
    let accent: Color

    private let maximum: Double = 240

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.16), lineWidth: 14)

            Circle()
                .trim(from: 0, to: min(1, max(0, speed / maximum)))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: speed)

            VStack(spacing: 2) {
                Text("\(Int(speed))")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km/h")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
    }
}

// MARK: - Garaje / elección de coche al empezar

struct GarageSetupView: View {
    @EnvironmentObject private var vehicles: VehicleStore
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String
    @State private var brandModel: String
    @State private var plate: String
    @State private var design: VehicleDesign
    @State private var accentRaw: String

    private let isEditing: Bool

    init(vehicle: Vehicle? = nil) {
        isEditing = vehicle != nil
        _nickname = State(initialValue: vehicle?.nickname ?? "Mi coche")
        _brandModel = State(initialValue: vehicle?.brandModel ?? "")
        _plate = State(initialValue: vehicle?.plate ?? "")
        _design = State(initialValue: vehicle?.design ?? .neutral)
        _accentRaw = State(initialValue: vehicle?.accentRaw ?? "blue")
    }

    private var accent: Color {
        AppAccent(rawValue: accentRaw)?.color ?? design.color
    }

    var body: some View {
        ZStack {
            CockpitBackground(accent: accent)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: design.icon)
                            .font(.system(size: 56))
                            .foregroundStyle(accent)
                            .shadow(color: accent.opacity(0.5), radius: 18)
                        Text(isEditing ? "Editar vehículo" : "Elige tu coche")
                            .font(.title.bold())
                        Text("Configura tu SEAT Ibiza 40 Aniversario 2024 con llantas de 16\". El estilo se aplica al salpicadero y a los widgets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    CockpitCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MARCA Y MODELO")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 12
                            ) {
                                ForEach(VehicleDesign.allCases.filter { $0 == .sport }) { item in
                                    Button {
                                        design = item
                                        switch item {
                                        case .sport: accentRaw = "red"
                                        case .luxury: accentRaw = "purple"
                                        case .electric: accentRaw = "green"
                                        case .suv, .classic: accentRaw = "orange"
                                        case .neutral: accentRaw = "blue"
                                        }
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: item.icon)
                                                .font(.title2)
                                            Text(item.title)
                                                .font(.subheadline.bold())
                                            Text(item.tagline)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(12)
                                        .background(
                                            design == item
                                                ? item.color.opacity(0.25)
                                                : Color.white.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(
                                                    design == item ? item.color : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    CockpitCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DATOS")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Button {
                                nickname = "Mi Ibiza"
                                brandModel = "SEAT Ibiza"
                                design = .sport
                                accentRaw = "red"
                            } label: {
                                Label("Usar SEAT Ibiza", systemImage: "car.sport.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)

                            TextField("Nombre (Mi coche)", text: $nickname)
                                .textFieldStyle(.roundedBorder)
                            TextField("Marca y modelo (opcional)", text: $brandModel)
                                .textFieldStyle(.roundedBorder)
                            TextField("Matrícula (opcional)", text: $plate)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)

                            Text("COLOR DE ACENTO")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            HStack(spacing: 14) {
                                ForEach(AppAccent.allCases) { item in
                                    Button {
                                        accentRaw = item.rawValue
                                    } label: {
                                        Circle()
                                            .fill(item.color)
                                            .frame(width: 30, height: 30)
                                            .overlay(
                                                Circle()
                                                    .stroke(.white, lineWidth: accentRaw == item.rawValue ? 3 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Button {
                        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                        let vehicle = Vehicle(
                            id: vehicles.vehicle?.id ?? UUID(),
                            nickname: trimmed.isEmpty ? "Mi coche" : trimmed,
                            brandModel: brandModel.trimmingCharacters(in: .whitespacesAndNewlines),
                            plate: plate.trimmingCharacters(in: .whitespacesAndNewlines),
                            design: design,
                            accentRaw: accentRaw
                        )
                        vehicles.save(vehicle)
                        UserDefaults.standard.set(accentRaw, forKey: "drivedeck.accent")
                        dismiss()
                    } label: {
                        Text(isEditing ? "Guardar vehículo" : "Continuar")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(accent, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 30)
                }
                .padding()
            }
        }
    }
}

// MARK: - Mis datos

struct VehicleBadge: View {
    let vehicle: Vehicle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [vehicle.accent, vehicle.accent.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: vehicle.design.icon)
                .font(.system(size: 54))
                .foregroundStyle(.white)
        }
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.25), lineWidth: 2)
        )
        .shadow(color: vehicle.accent.opacity(0.45), radius: 22, y: 8)
    }
}

struct MyDataView: View {
    @EnvironmentObject private var vehicles: VehicleStore
    @EnvironmentObject private var trips: TripStore
    @State private var showingGarage = false

    private var vehicle: Vehicle? { vehicles.vehicle }
    private var accent: Color { vehicle?.accent ?? .red }

    private var totalDistance: Double {
        trips.trips.reduce(0) { $0 + $1.distanceMeters }
    }

    private var bestScore: Int {
        trips.trips.map(\.score).max() ?? 0
    }

    var body: some View {
        ZStack {
            CockpitBackground(accent: accent)

            ScrollView {
                VStack(spacing: 20) {
                    if let vehicle {
                        VStack(spacing: 14) {
                            VehicleBadge(vehicle: vehicle)
                            VStack(spacing: 4) {
                                Text(vehicle.brandModel.isEmpty ? vehicle.nickname : vehicle.brandModel)
                                    .font(.title2.bold())
                                Text(vehicle.nickname)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 16)

                        CockpitCard {
                            VStack(spacing: 12) {
                                DataRow(title: "Vehículo", value: vehicle.brandModel.isEmpty ? vehicle.nickname : vehicle.brandModel)
                                Divider().background(Color.white.opacity(0.1))
                                DataRow(title: "Matrícula", value: vehicle.plate.isEmpty ? "Sin matrícula" : vehicle.plate)
                                Divider().background(Color.white.opacity(0.1))
                                DataRow(title: "Diseño", value: vehicle.design.title)
                                Divider().background(Color.white.opacity(0.1))
                                DataRow(title: "Color", value: AppAccent(rawValue: vehicle.accentRaw)?.label ?? "Rojo")
                            }
                        }

                        CockpitCard {
                            HStack {
                                CockpitStat(title: "Viajes", value: "\(trips.trips.count)", accent: accent)
                                CockpitStat(title: "Distancia", value: trips.distanceText(totalDistance), accent: accent)
                                CockpitStat(title: "Mejor", value: bestScore == 0 ? "—" : "\(bestScore)", accent: accent)
                            }
                        }

                        Button {
                            showingGarage = true
                        } label: {
                            Label("Editar mis datos", systemImage: "pencil")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(accent, in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.white)
                        }

                        Text("Tus datos se guardan solo en este iPhone. No hay cuentas ni servidores.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Mis datos")
        .sheet(isPresented: $showingGarage) {
            GarageSetupView(vehicle: vehicles.vehicle)
                .environmentObject(vehicles)
        }
    }
}

struct DataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

// MARK: - Salpicadero de inicio

struct HomeView: View {
    @EnvironmentObject private var vehicles: VehicleStore
    @EnvironmentObject private var trips: TripStore
    @EnvironmentObject private var media: MediaStore
    @Binding var selectedTab: Int

    @State private var showingGarage = false

    private var vehicle: Vehicle? { vehicles.vehicle }
    private var accent: Color { vehicle?.accent ?? .blue }
    private var design: VehicleDesign { vehicle?.design ?? .neutral }

    var body: some View {
        ZStack {
            CockpitBackground(accent: accent)

            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hola,")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(vehicle?.nickname ?? "Mi coche")
                                .font(.title2.bold())
                        }
                        Spacer()
                        Button {
                            showingGarage = true
                        } label: {
                            Image(systemName: "car.fill")
                                .font(.title3)
                                .foregroundStyle(accent)
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.top, 8)

                    if let vehicle {
                        CockpitCard {
                            HStack(spacing: 14) {
                                Image(systemName: design.icon)
                                    .font(.system(size: 40))
                                    .foregroundStyle(design.color)
                                    .frame(width: 62, height: 62)
                                    .background(design.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(design.title.uppercased())
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(design.color)
                                    Text(vehicle.brandModel.isEmpty ? vehicle.nickname : vehicle.brandModel)
                                        .font(.headline)
                                    if !vehicle.plate.isEmpty {
                                        Text(vehicle.plate)
                                            .font(.subheadline.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Editar") { showingGarage = true }
                                    .font(.caption.bold())
                                    .buttonStyle(.bordered)
                            }
                        }
                    }

                    CockpitCard {
                        VStack(spacing: 12) {
                            SpeedRing(speed: trips.liveSpeedKmh, accent: accent)

                            HStack(spacing: 10) {
                                CockpitStat(title: "Distancia", value: trips.isRecording ? trips.distanceText(trips.currentDistance) : "—", accent: accent)
                                CockpitStat(title: "Duración", value: trips.isRecording ? trips.durationText(trips.currentDuration) : "—", accent: accent)
                                CockpitStat(title: "Puntos", value: trips.trips.first.map { "\($0.score)" } ?? "—", accent: accent)
                            }

                            Button {
                                trips.isRecording ? trips.stopRecording() : trips.startRecording()
                            } label: {
                                HStack {
                                    Image(systemName: trips.isRecording ? "stop.fill" : "record.circle")
                                    Text(trips.isRecording ? "Detener viaje" : "Empezar viaje")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(13)
                                .background(trips.isRecording ? Color.red : accent, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                            }
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        QuickAction(title: "Vídeo y AirPlay", icon: "tv.fill", color: .blue) { selectedTab = 2 }
                        QuickAction(title: "Mis datos", icon: "car.sport.fill", color: .red) { selectedTab = 1 }
                        QuickAction(title: "Mis viajes", icon: "map.fill", color: .purple) { selectedTab = 3 }
                        QuickAction(title: "Widgets", icon: "square.grid.2x2.fill", color: .orange) { selectedTab = 4 }
                        QuickAction(title: "Sonidos", icon: "speaker.wave.2.fill", color: .green) { selectedTab = 5 }
                    }

                    if let last = trips.trips.first {
                        CockpitCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Último viaje", systemImage: "clock.arrow.circlepath")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(last.score)/100")
                                        .font(.headline.bold())
                                        .foregroundStyle(accent)
                                }
                                RouteMap(points: last.points.map(\.clLocation))
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text("\(trips.distanceText(last.distanceMeters)) · \(last.durationText) · \(last.start.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("DriveDeck")
        .sheet(isPresented: $showingGarage) {
            GarageSetupView(vehicle: vehicles.vehicle)
                .environmentObject(vehicles)
        }
    }
}

struct CockpitStat: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.09))
            )
        }
        .buttonStyle(.plain)
    }
}
