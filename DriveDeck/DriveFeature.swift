import SwiftUI
import UIKit
import CoreLocation
import CoreMotion
import MapKit

// MARK: - Modelos

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
    }
}

enum HarshKind: String, Codable {
    case acceleration = "Aceleración"
    case braking = "Frenada"
    case cornering = "Curva"
}

struct HarshEvent: Codable, Identifiable, Hashable {
    let id: UUID
    var kind: HarshKind
    var date: Date
    var magnitude: Double

    init(id: UUID = UUID(), kind: HarshKind, date: Date = Date(), magnitude: Double) {
        self.id = id
        self.kind = kind
        self.date = date
        self.magnitude = magnitude
    }
}

struct Trip: Codable, Identifiable, Hashable {
    let id: UUID
    var start: Date
    var end: Date
    var points: [Coordinate]
    var distanceMeters: Double
    var duration: TimeInterval
    var maxSpeedKmh: Double
    var averageSpeedKmh: Double
    var events: [HarshEvent]
    var score: Int

    var distanceText: String {
        let value = distanceMeters / 1000
        return String(format: "%.2f km", value)
    }

    var durationText: String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

// MARK: - Location

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var onLocation: ((CLLocation) -> Void)?
    @Published var status: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        status = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.onLocation?(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.status = manager.authorizationStatus }
    }
}

// MARK: - Motion

final class MotionManager {
    private let motion = CMMotionManager()
    var onEvent: ((HarshKind, Double) -> Void)?
    private var lastEvent = Date.distantPast

    func start() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }
            let x = acceleration.x
            let y = acceleration.y
            let z = acceleration.z
            Task { @MainActor in self.evaluate(x: x, y: y, z: z) }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }

    @MainActor
    private func evaluate(x: Double, y: Double, z: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastEvent) > 2 else { return }

        let magnitude = sqrt(x * x + y * y + z * z)

        var kind: HarshKind?
        var value = 0.0
        if magnitude > 1.9 {
            kind = .cornering
            value = magnitude
        } else if y > 1.6 {
            kind = .braking
            value = y
        } else if y < -1.6 {
            kind = .acceleration
            value = abs(y)
        }

        if let kind {
            lastEvent = now
            onEvent?(kind, value)
        }
    }
}

// MARK: - Store de viajes

@MainActor
final class TripStore: ObservableObject {
    static let shared = TripStore()

    @Published var trips: [Trip] = []
    @Published var isRecording = false
    @Published var currentDistance: Double = 0
    @Published var currentDuration: TimeInterval = 0
    @Published var currentPoints: [Coordinate] = []
    @Published var currentEvents: [HarshEvent] = []
    @Published var liveSpeedKmh: Double = 0
    @Published var useKilometers = true
    @Published var message: String?

    private let locationManager = LocationManager()
    private let motionManager = MotionManager()
    private var startDate: Date?
    private var lastLocation: CLLocation?
    private var maxSpeedKmh: Double = 0
    private var speedSamples: [Double] = []

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        load()
        locationManager.onLocation = { [weak self] location in
            self?.ingest(location)
        }
        motionManager.onEvent = { [weak self] kind, magnitude in
            self?.addEvent(kind: kind, magnitude: magnitude)
        }
    }

    // MARK: Persistencia

    private func load() {
        let url = documents.appendingPathComponent("trips.json")
        guard let data = try? Data(contentsOf: url) else { return }
        trips = (try? JSONDecoder().decode([Trip].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        try? data.write(to: documents.appendingPathComponent("trips.json"), options: .atomic)
    }

    // MARK: Grabación

    func startRecording() {
        guard !isRecording else { return }
        locationManager.requestPermission()
        startDate = Date()
        lastLocation = nil
        currentDistance = 0
        currentDuration = 0
        currentPoints = []
        currentEvents = []
        liveSpeedKmh = 0
        maxSpeedKmh = 0
        speedSamples = []
        isRecording = true
        locationManager.start()
        motionManager.start()
        message = "Grabando viaje…"
    }

    func stopRecording() {
        guard isRecording, let start = startDate else { return }
        locationManager.stop()
        motionManager.stop()
        isRecording = false

        let average = speedSamples.isEmpty ? 0 : speedSamples.reduce(0, +) / Double(speedSamples.count)
        let penalty = currentEvents.reduce(0) { total, event in
            total + (event.kind == .cornering ? 4 : 5)
        }
        let score = max(0, min(100, 100 - penalty))
        let trip = Trip(
            id: UUID(),
            start: start,
            end: Date(),
            points: currentPoints,
            distanceMeters: currentDistance,
            duration: Date().timeIntervalSince(start),
            maxSpeedKmh: maxSpeedKmh,
            averageSpeedKmh: average,
            events: currentEvents,
            score: score
        )
        trips.insert(trip, at: 0)
        save()
        startDate = nil
        message = "Viaje guardado · puntuación \(score)/100"
    }

    private func ingest(_ location: CLLocation) {
        guard isRecording else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 65 else { return }

        let speed = max(0, location.speed) * 3.6
        liveSpeedKmh = speed
        speedSamples.append(speed)
        maxSpeedKmh = max(maxSpeedKmh, speed)

        if let previous = lastLocation {
            let delta = location.distance(from: previous)
            if delta < 500 { currentDistance += delta }
        }
        lastLocation = location
        currentPoints.append(Coordinate(location))
        if let start = startDate { currentDuration = Date().timeIntervalSince(start) }
    }

    private func addEvent(kind: HarshKind, magnitude: Double) {
        guard isRecording else { return }
        currentEvents.append(HarshEvent(kind: kind, magnitude: magnitude))
    }

    func removeTrip(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        save()
    }

    func clearAll() {
        trips = []
        save()
    }

    var allCoordinates: [CLLocationCoordinate2D] {
        trips.flatMap { $0.points.map(\.clLocation) }
    }

    func distanceText(_ meters: Double) -> String {
        if useKilometers {
            return String(format: "%.2f km", meters / 1000)
        }
        let miles = meters / 1609.344
        return String(format: "%.2f mi", miles)
    }

    func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    func speedText(_ kmh: Double) -> String {
        if useKilometers {
            return String(format: "%.0f km/h", kmh)
        }
        return String(format: "%.0f mph", kmh / 1.609344)
    }

    func shareText(for trip: Trip) -> String {
        """
        DriveDeck · viaje del \(trip.start.formatted(date: .abbreviated, time: .shortened))
        Distancia: \(distanceText(trip.distanceMeters)) · Duración: \(trip.durationText)
        Velocidad media: \(speedText(trip.averageSpeedKmh)) · Máxima: \(speedText(trip.maxSpeedKmh))
        Puntuación: \(trip.score)/100 · Incidentes: \(trip.events.count)
        """
    }
}

// MARK: - Mapas

struct RouteMap: UIViewRepresentable {
    let points: [CLLocationCoordinate2D]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard points.count > 1 else { return }
        let polyline = MKPolyline(coordinates: points, count: points.count)
        map.addOverlay(polyline)
        let rect = polyline.boundingMapRect
        let region = MKCoordinateRegion(rect)
        map.setRegion(map.regionThatFits(region), animated: context.coordinator.didRender)
        context.coordinator.didRender = true
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var didRender = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue
            renderer.lineWidth = 4
            return renderer
        }
    }
}

struct TerritoryMap: UIViewRepresentable {
    let routes: [[CLLocationCoordinate2D]]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        for route in routes where route.count > 1 {
            map.addOverlay(MKPolyline(coordinates: route, count: route.count))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemPurple.withAlphaComponent(0.75)
            renderer.lineWidth = 3
            return renderer
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Pantalla Drive

struct DriveView: View {
    @EnvironmentObject private var trips: TripStore
    @State private var showingTerritory = false
    @State private var shareItem: IdentifiedString?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(trips.isRecording ? "Grabando viaje" : "Listo para grabar")
                                    .font(.headline)
                                Text(trips.isRecording ? "Velocidad actual \(trips.speedText(trips.liveSpeedKmh))" : "Los viajes se graban en segundo plano con permiso «Siempre».")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                trips.isRecording ? trips.stopRecording() : trips.startRecording()
                            } label: {
                                Image(systemName: trips.isRecording ? "stop.circle.fill" : "record.circle")
                                    .font(.system(size: 44))
                                    .foregroundStyle(trips.isRecording ? .red : .accentColor)
                            }
                        }
                        if trips.isRecording {
                            HStack {
                                StatBox(title: "Distancia", value: trips.distanceText(trips.currentDistance))
                                StatBox(title: "Duración", value: trips.durationText(trips.currentDuration))
                                StatBox(title: "Eventos", value: "\(trips.currentEvents.count)")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Mapa de territorio") {
                    Button {
                        showingTerritory = true
                    } label: {
                        Label("Ver mi territorio (\(trips.trips.count) viajes)", systemImage: "map")
                    }
                    Toggle("Millas en lugar de km", isOn: Binding(
                        get: { !trips.useKilometers },
                        set: { trips.useKilometers = !$0 }
                    ))
                }

                Section("Viajes") {
                    if trips.trips.isEmpty {
                        Text("Todavía no hay viajes. Pulsa el botón rojo para empezar.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(trips.trips) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(trip.start.formatted(date: .abbreviated, time: .shortened))
                                        Text("\(trips.distanceText(trip.distanceMeters)) · \(trip.durationText)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(trip.score)")
                                        .font(.title3.bold())
                                        .foregroundStyle(scoreColor(trip.score))
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet { trips.removeTrip(trips.trips[index]) }
                        }
                    }
                }

                if let message = trips.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("DriveDeck · Drive")
            .sheet(isPresented: $showingTerritory) {
                NavigationStack {
                    TerritoryMap(routes: trips.trips.map { $0.points.map(\.clLocation) })
                        .ignoresSafeArea()
                        .navigationTitle("Mi territorio")
                        .toolbar {
                            Button("Cerrar") { showingTerritory = false }
                        }
                }
            }
            .sheet(item: $shareItem) { identified in
                ShareSheet(items: [identified.value])
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return .green }
        if score >= 65 { return .orange }
        return .red
    }
}

struct IdentifiedString: Identifiable {
    let id = UUID()
    let value: String
}

struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var trips: TripStore
    let trip: Trip

    var body: some View {
        List {
            Section {
                RouteMap(points: trip.points.map(\.clLocation))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Section("Resumen") {
                HStack {
                    StatBox(title: "Puntuación", value: "\(trip.score)/100")
                    StatBox(title: "Distancia", value: trips.distanceText(trip.distanceMeters))
                    StatBox(title: "Duración", value: trip.durationText)
                }
                HStack {
                    StatBox(title: "Media", value: trips.speedText(trip.averageSpeedKmh))
                    StatBox(title: "Máxima", value: trips.speedText(trip.maxSpeedKmh))
                    StatBox(title: "Eventos", value: "\(trip.events.count)")
                }
            }
            Section("Conducción") {
                if trip.events.isEmpty {
                    Text("Sin aceleraciones, frenadas o curvas bruscas detectadas.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trip.events) { event in
                        HStack {
                            Image(systemName: event.kind == .braking ? "arrow.down.right" : event.kind == .acceleration ? "arrow.up.right" : "arrow.turn.up.right")
                            Text(event.kind.rawValue)
                            Spacer()
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Compartir resumen") {
                    shareItem = IdentifiedString(value: trips.shareText(for: trip))
                }
            }
        }
        .navigationTitle("Viaje")
        .sheet(item: $shareItem) { identified in
            ShareSheet(items: [identified.value])
        }
    }

    @State private var shareItem: IdentifiedString?
}
