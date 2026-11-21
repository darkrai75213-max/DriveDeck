import SwiftUI
import UIKit
import CoreLocation
import CoreMotion
import MapKit
import UserNotifications

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
    var direction: String?
    var date: Date
    var magnitude: Double

    init(id: UUID = UUID(), kind: HarshKind, direction: String? = nil, date: Date = Date(), magnitude: Double) {
        self.id = id
        self.kind = kind
        self.direction = direction
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

    // Telemetría avanzada (todo lo que aportan los sensores del iPhone)
    var maxG: Double
    var maxLateralG: Double
    var maxLongitudinalG: Double
    var maxRotationRate: Double
    var altitudeGain: Double
    var minAltitude: Double
    var maxAltitude: Double
    var sampleCount: Int
    var steps: Int
    var drivingTime: TimeInterval
    var idleTime: TimeInterval

    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        points: [Coordinate],
        distanceMeters: Double,
        duration: TimeInterval,
        maxSpeedKmh: Double,
        averageSpeedKmh: Double,
        events: [HarshEvent],
        score: Int,
        maxG: Double = 0,
        maxLateralG: Double = 0,
        maxLongitudinalG: Double = 0,
        maxRotationRate: Double = 0,
        altitudeGain: Double = 0,
        minAltitude: Double = 0,
        maxAltitude: Double = 0,
        sampleCount: Int = 0,
        steps: Int = 0,
        drivingTime: TimeInterval = 0,
        idleTime: TimeInterval = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.points = points
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.maxSpeedKmh = maxSpeedKmh
        self.averageSpeedKmh = averageSpeedKmh
        self.events = events
        self.score = score
        self.maxG = maxG
        self.maxLateralG = maxLateralG
        self.maxLongitudinalG = maxLongitudinalG
        self.maxRotationRate = maxRotationRate
        self.altitudeGain = altitudeGain
        self.minAltitude = minAltitude
        self.maxAltitude = maxAltitude
        self.sampleCount = sampleCount
        self.steps = steps
        self.drivingTime = drivingTime
        self.idleTime = idleTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        points = try c.decode([Coordinate].self, forKey: .points)
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        maxSpeedKmh = try c.decode(Double.self, forKey: .maxSpeedKmh)
        averageSpeedKmh = try c.decode(Double.self, forKey: .averageSpeedKmh)
        events = try c.decode([HarshEvent].self, forKey: .events)
        score = try c.decode(Int.self, forKey: .score)
        maxG = try c.decodeIfPresent(Double.self, forKey: .maxG) ?? 0
        maxLateralG = try c.decodeIfPresent(Double.self, forKey: .maxLateralG) ?? 0
        maxLongitudinalG = try c.decodeIfPresent(Double.self, forKey: .maxLongitudinalG) ?? 0
        maxRotationRate = try c.decodeIfPresent(Double.self, forKey: .maxRotationRate) ?? 0
        altitudeGain = try c.decodeIfPresent(Double.self, forKey: .altitudeGain) ?? 0
        minAltitude = try c.decodeIfPresent(Double.self, forKey: .minAltitude) ?? 0
        maxAltitude = try c.decodeIfPresent(Double.self, forKey: .maxAltitude) ?? 0
        sampleCount = try c.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        drivingTime = try c.decodeIfPresent(TimeInterval.self, forKey: .drivingTime) ?? 0
        idleTime = try c.decodeIfPresent(TimeInterval.self, forKey: .idleTime) ?? 0
    }

    var leftCurves: Int { events.filter { $0.kind == .cornering && $0.direction == "izquierda" }.count }
    var rightCurves: Int { events.filter { $0.kind == .cornering && $0.direction == "derecha" }.count }
    var hardBrakes: Int { events.filter { $0.kind == .braking }.count }
    var hardAccelerations: Int { events.filter { $0.kind == .acceleration }.count }

    var distanceText: String { String(format: "%.2f km", distanceMeters / 1000) }

    var durationText: String {
        let total = Int(duration)
        if total < 3600 { return "\(total / 60) min \(total % 60) s" }
        return "\(total / 3600) h \((total % 3600) / 60) min"
    }
}

// MARK: - Location

final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var onLocation: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    func requestPermission() { manager.requestAlwaysAuthorization() }

    func start() {
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { self.onLocation?(location) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}

// MARK: - Motion (todos los sensores disponibles)

struct MotionSample {
    var ax = 0.0, ay = 0.0, az = 0.0       // acelerómetro (g)
    var magnitude = 0.0                     // magnitud del vector de aceleración
    var rotationZ = 0.0                     // gyroscopio (rad/s)
    var altitude: Double?                   // altímetro relativo (m)
    var steps = 0                           // podómetro
}

final class MotionManager {
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let eventQueue = DispatchQueue(label: "drivedeck.motion.events")

    var onSample: ((MotionSample) -> Void)?
    var onActivity: ((Bool) -> Void)?        // true = conduciendo
    private var lastEvent = Date.distantPast
    private var lastAltitude: Double?

    func start() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let d = data else { return }
                var sample = MotionSample()
                sample.ax = d.userAcceleration.x
                sample.ay = d.userAcceleration.y
                sample.az = d.userAcceleration.z
                sample.rotationZ = d.rotationRate.z
                sample.magnitude = sqrt(sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az)
                self.onSample?(sample)
                self.evaluate(sample)
            }
        } else if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.1
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                var sample = MotionSample()
                sample.ax = a.x; sample.ay = a.y; sample.az = a.z
                sample.magnitude = sqrt(sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az)
                self.onSample?(sample)
                self.evaluate(sample)
            }
        }

        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let alt = data else { return }
                let meters = alt.relativeAltitude.doubleValue
                var sample = MotionSample()
                sample.altitude = meters
                self?.lastAltitude = meters
                self?.onSample?(sample)
            }
        }

        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let data else { return }
                var sample = MotionSample()
                sample.steps = data.numberOfSteps.intValue
                self?.onSample?(sample)
            }
        }

        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                self?.onActivity?(activity.automotive && !activity.stationary)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
    }

    private func evaluate(_ sample: MotionSample) {
        let now = Date()
        guard now.timeIntervalSince(lastEvent) > 2 else { return }

        let magnitude = sample.magnitude
        var kind: HarshKind?
        var direction: String?
        if abs(sample.rotationZ) > 0.85 {
            kind = .cornering
            direction = sample.rotationZ > 0 ? "izquierda" : "derecha"
        } else if sample.ay > 0.55 {
            kind = .braking
        } else if sample.ay < -0.55 {
            kind = .acceleration
        } else if magnitude > 1.9 {
            kind = .cornering
            direction = sample.ax > 0 ? "izquierda" : "derecha"
        }

        if let kind {
            lastEvent = now
            let handler = onEvent
            eventQueue.async { handler?(kind, direction, magnitude) }
        }
    }

    var onEvent: ((HarshKind, String?, Double) -> Void)?
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
    @Published var autoDetect = true
    @Published var message: String?

    // métricas en directo
    @Published var currentMaxG = 0.0
    @Published var currentMaxLateralG = 0.0
    @Published var currentMaxRotation = 0.0
    @Published var currentAltitude = 0.0

    private let locationManager = LocationManager()
    private let motionManager = MotionManager()
    private var startDate: Date?
    private var lastLocation: CLLocation?
    private var maxSpeedKmh = 0.0
    private var speedSamples: [Double] = []
    private var telemetry = Telemetry()
    private var autoSpeedHits = 0
    private var stationarySince: Date?
    private var monitoring = false

    private struct Telemetry {
        var maxG = 0.0
        var maxLateralG = 0.0
        var maxLongitudinalG = 0.0
        var maxRotation = 0.0
        var altitudes: [Double] = []
        var steps = 0
        var drivingTime = 0.0
        var idleTime = 0.0
        var samples = 0
    }

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        load()
        useKilometers = UserDefaults.standard.object(forKey: "drivedeck.use.km") as? Bool ?? true
        autoDetect = UserDefaults.standard.object(forKey: "drivedeck.auto.trips") as? Bool ?? true

        locationManager.onLocation = { [weak self] location in
            guard let self else { return }
            self.ingest(location)
            if self.autoDetect && !self.isRecording { self.evaluateAutoStart(speed: location.speed * 3.6) }
        }
        motionManager.onSample = { [weak self] sample in
            Task { @MainActor in self?.ingestMotion(sample) }
        }
        motionManager.onEvent = { [weak self] kind, direction, magnitude in
            Task { @MainActor in
                self?.addEvent(kind: kind, direction: direction, magnitude: magnitude)
            }
        }
        motionManager.onActivity = { [weak self] driving in
            Task { @MainActor in
                guard let self, self.autoDetect, !self.isRecording else { return }
                if driving { self.autoSpeedHits += 1 }
            }
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

    func setUseKilometers(_ value: Bool) {
        useKilometers = value
        UserDefaults.standard.set(value, forKey: "drivedeck.use.km")
    }

    func setAutoDetect(_ value: Bool) {
        autoDetect = value
        UserDefaults.standard.set(value, forKey: "drivedeck.auto.trips")
        if value { startMonitoringIfNeeded() } else { stopMonitoring() }
    }

    // MARK: Monitorización para arranque automático

    func startMonitoringIfNeeded() {
        guard autoDetect, !monitoring else { return }
        locationManager.requestPermission()
        locationManager.start()
        motionManager.start()
        monitoring = true
        message = "Detección automática activada"
    }

    func stopMonitoring() {
        guard monitoring, !isRecording else { return }
        locationManager.stop()
        motionManager.stop()
        monitoring = false
    }

    private func evaluateAutoStart(speed: Double) {
        guard speed > 18 else {
            autoSpeedHits = max(0, autoSpeedHits - 1)
            return
        }
        autoSpeedHits += 1
        if autoSpeedHits >= 3 {
            autoSpeedHits = 0
            startRecording(automatic: true)
        }
    }

    // MARK: Grabación

    func startRecording(automatic: Bool = false) {
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
        telemetry = Telemetry()
        stationarySince = nil
        isRecording = true
        if !monitoring {
            locationManager.start()
            motionManager.start()
        }
        message = automatic ? "Viaje iniciado automáticamente" : "Grabando viaje…"
    }

    func stopRecording() {
        guard isRecording, let start = startDate else { return }
        if !autoDetect {
            locationManager.stop()
            motionManager.stop()
        }
        isRecording = false

        let average = speedSamples.isEmpty ? 0 : speedSamples.reduce(0, +) / Double(speedSamples.count)
        let penalty = currentEvents.reduce(0) { $0 + ($1.kind == .cornering ? 4 : 5) }
        let score = max(0, min(100, 100 - penalty))
        let altitudes = telemetry.altitudes
        let minAlt = altitudes.min() ?? 0
        let maxAlt = altitudes.max() ?? 0

        let trip = Trip(
            start: start,
            end: Date(),
            points: currentPoints,
            distanceMeters: currentDistance,
            duration: Date().timeIntervalSince(start),
            maxSpeedKmh: maxSpeedKmh,
            averageSpeedKmh: average,
            events: currentEvents,
            score: score,
            maxG: telemetry.maxG,
            maxLateralG: telemetry.maxLateralG,
            maxLongitudinalG: telemetry.maxLongitudinalG,
            maxRotationRate: telemetry.maxRotation,
            altitudeGain: maxAlt - minAlt,
            minAltitude: minAlt,
            maxAltitude: maxAlt,
            sampleCount: telemetry.samples,
            steps: telemetry.steps,
            drivingTime: telemetry.drivingTime,
            idleTime: telemetry.idleTime
        )
        trips.insert(trip, at: 0)
        save()
        startDate = nil
        message = "Viaje guardado · \(score)/100"
        sendNotification(for: trip)
        if autoDetect { stationarySince = nil }
    }

    private func ingest(_ location: CLLocation) {
        if isRecording {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 65 else { return }
            let speed = max(0, location.speed) * 3.6
            liveSpeedKmh = speed
            speedSamples.append(speed)
            maxSpeedKmh = max(maxSpeedKmh, speed)
            if speed > 5 { telemetry.drivingTime += 1 } else { telemetry.idleTime += 1 }

            if let previous = lastLocation {
                let delta = location.distance(from: previous)
                if delta < 500 { currentDistance += delta }
            }
            lastLocation = location
            currentPoints.append(Coordinate(location))
            if let start = startDate { currentDuration = Date().timeIntervalSince(start) }

            if autoDetect {
                if speed < 3 {
                    if stationarySince == nil { stationarySince = Date() }
                    else if let since = stationarySince, Date().timeIntervalSince(since) > 180 {
                        stopRecording()
                    }
                } else {
                    stationarySince = nil
                }
            }
        } else {
            liveSpeedKmh = max(0, location.speed) * 3.6
        }
    }

    private func ingestMotion(_ sample: MotionSample) {
        guard isRecording else { return }
        telemetry.samples += 1
        let g = sqrt(sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az)
        telemetry.maxG = max(telemetry.maxG, g)
        telemetry.maxLateralG = max(telemetry.maxLateralG, abs(sample.ax))
        telemetry.maxLongitudinalG = max(telemetry.maxLongitudinalG, abs(sample.ay))
        telemetry.maxRotation = max(telemetry.maxRotation, abs(sample.rotationZ))
        if let alt = sample.altitude { telemetry.altitudes.append(alt); currentAltitude = alt }
        telemetry.steps = max(telemetry.steps, sample.steps)
        currentMaxG = telemetry.maxG
        currentMaxLateralG = telemetry.maxLateralG
        currentMaxRotation = telemetry.maxRotation
    }

    private func addEvent(kind: HarshKind, direction: String?, magnitude: Double) {
        guard isRecording else { return }
        currentEvents.append(HarshEvent(kind: kind, direction: direction, magnitude: magnitude))
    }

    private func sendNotification(for trip: Trip) {
        let content = UNMutableNotificationContent()
        content.title = "Viaje guardado · \(trip.score)/100"
        content.body = "\(distanceText(trip.distanceMeters)) · \(trip.durationText) · Máx \(speedText(trip.maxSpeedKmh)) · \(trip.hardBrakes) frenazos · \(trip.leftCurves + trip.rightCurves) curvas"
        content.sound = .default
        content.badge = 1
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
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

    var totalDistance: Double { trips.reduce(0) { $0 + $1.distanceMeters } }

    func distanceText(_ meters: Double) -> String {
        if useKilometers { return String(format: "%.2f km", meters / 1000) }
        return String(format: "%.2f mi", meters / 1609.344)
    }

    func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    func speedText(_ kmh: Double) -> String {
        if useKilometers { return String(format: "%.0f km/h", kmh) }
        return String(format: "%.0f mph", kmh / 1.609344)
    }

    func shareText(for trip: Trip) -> String {
        """
        DriveDeck · viaje del \(trip.start.formatted(date: .abbreviated, time: .shortened))
        Distancia: \(distanceText(trip.distanceMeters)) · Duración: \(trip.durationText)
        Media: \(speedText(trip.averageSpeedKmh)) · Máxima: \(speedText(trip.maxSpeedKmh))
        Curvas izq/der: \(trip.leftCurves)/\(trip.rightCurves) · Frenazos: \(trip.hardBrakes) · Acelerones: \(trip.hardAccelerations)
        G máx: \(String(format: "%.2f", trip.maxG)) g · Desnivel: \(String(format: "%.0f", trip.altitudeGain)) m
        Puntuación: \(trip.score)/100
        """
    }
}

// MARK: - Mapas y compartir

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
        let region = MKCoordinateRegion(polyline.boundingMapRect)
        map.setRegion(map.regionThatFits(region), animated: context.coordinator.didRender)
        context.coordinator.didRender = true
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var didRender = false
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemRed
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
            renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.7)
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
            Text(value).font(.subheadline.bold()).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Pantalla Recorrido

struct TripView: View {
    @EnvironmentObject private var trips: TripStore
    @State private var showingTerritory = false

    var body: some View {
        NavigationStack {
            ZStack {
                CockpitBackground(accent: .red)
                List {
                    Section {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trips.isRecording ? "Grabando recorrido" : "Listo para grabar")
                                        .font(.headline)
                                    Text(trips.isRecording
                                         ? "\(trips.speedText(trips.liveSpeedKmh)) · \(trips.distanceText(trips.currentDistance))"
                                         : "Detección automática activada: empieza a conducir y se grabará solo.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    trips.isRecording ? trips.stopRecording() : trips.startRecording()
                                } label: {
                                    Image(systemName: trips.isRecording ? "stop.circle.fill" : "record.circle")
                                        .font(.system(size: 46))
                                        .foregroundStyle(trips.isRecording ? .red : Color.accentColor)
                                }
                            }
                            if trips.isRecording {
                                HStack {
                                    StatBox(title: "Distancia", value: trips.distanceText(trips.currentDistance))
                                    StatBox(title: "Tiempo", value: trips.durationText(trips.currentDuration))
                                    StatBox(title: "G máx", value: String(format: "%.2f", trips.currentMaxG))
                                }
                                HStack {
                                    StatBox(title: "Máxima", value: trips.speedText(trips.liveSpeedKmh))
                                    StatBox(title: "Curvas", value: "\(trips.currentEvents.filter { $0.kind == .cornering }.count)")
                                    StatBox(title: "Altitud", value: String(format: "%.0f m", trips.currentAltitude))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Ajustes de grabación") {
                        Toggle("Detección automática al conducir", isOn: Binding(
                            get: { trips.autoDetect },
                            set: { trips.setAutoDetect($0) }
                        ))
                        Toggle("Mostrar siempre km/h", isOn: Binding(
                            get: { trips.useKilometers },
                            set: { trips.setUseKilometers($0) }
                        ))
                        Button("Ver mi territorio (\(trips.trips.count) viajes)") { showingTerritory = true }
                    }

                    Section("Recorridos") {
                        if trips.trips.isEmpty {
                            Text("Todavía no hay recorridos. Conduce y se grabarán automáticamente.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(trips.trips) { trip in
                                NavigationLink { TripDetailView(trip: trip) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(trip.start.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline.bold())
                                            Spacer()
                                            Text("\(trip.score)/100")
                                                .font(.headline.bold())
                                                .foregroundStyle(trip.score >= 85 ? .green : trip.score >= 65 ? .orange : .red)
                                        }
                                        RouteMap(points: trip.points.map(\.clLocation))
                                            .frame(height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .allowsHitTesting(false)
                                        HStack {
                                            Label(trips.distanceText(trip.distanceMeters), systemImage: "road.lanes")
                                            Label(trip.durationText, systemImage: "clock")
                                            Label(trips.speedText(trip.maxSpeedKmh), systemImage: "speedometer")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Recorrido")
            .onAppear { if trips.autoDetect { trips.startMonitoringIfNeeded() } }
            .sheet(isPresented: $showingTerritory) {
                NavigationStack {
                    TerritoryMap(routes: trips.trips.map { $0.points.map(\.clLocation) })
                        .ignoresSafeArea()
                        .navigationTitle("Mi territorio")
                        .toolbar { Button("Cerrar") { showingTerritory = false } }
                }
            }
        }
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var trips: TripStore
    let trip: Trip
    @State private var shareItem: IdentifiedString?

    var body: some View {
        List {
            Section {
                RouteMap(points: trip.points.map(\.clLocation))
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Section("Resumen") {
                HStack {
                    StatBox(title: "Distancia", value: trips.distanceText(trip.distanceMeters))
                    StatBox(title: "Duración", value: trip.durationText)
                    StatBox(title: "Puntuación", value: "\(trip.score)/100")
                }
                HStack {
                    StatBox(title: "Vel. media", value: trips.speedText(trip.averageSpeedKmh))
                    StatBox(title: "Vel. máxima", value: trips.speedText(trip.maxSpeedKmh))
                    StatBox(title: "Muestras", value: "\(trip.sampleCount)")
                }
            }
            Section("Conducción") {
                HStack {
                    StatBox(title: "Curvas izq.", value: "\(trip.leftCurves)")
                    StatBox(title: "Curvas der.", value: "\(trip.rightCurves)")
                    StatBox(title: "Frenazos", value: "\(trip.hardBrakes)")
                }
                HStack {
                    StatBox(title: "Acelerones", value: "\(trip.hardAccelerations)")
                    StatBox(title: "G máx", value: String(format: "%.2f g", trip.maxG))
                    StatBox(title: "G lateral", value: String(format: "%.2f g", trip.maxLateralG))
                }
                HStack {
                    StatBox(title: "G longitudinal", value: String(format: "%.2f g", trip.maxLongitudinalG))
                    StatBox(title: "Gyro Z", value: String(format: "%.2f rad/s", trip.maxRotationRate))
                    StatBox(title: "Desnivel", value: String(format: "%.0f m", trip.altitudeGain))
                }
                HStack {
                    StatBox(title: "Alt. mín.", value: String(format: "%.0f m", trip.minAltitude))
                    StatBox(title: "Alt. máx.", value: String(format: "%.0f m", trip.maxAltitude))
                    StatBox(title: "Conduciendo", value: trips.durationText(trip.drivingTime))
                }
                HStack {
                    StatBox(title: "Parado", value: trips.durationText(trip.idleTime))
                    StatBox(title: "Pasos", value: "\(trip.steps)")
                    StatBox(title: "Incidentes", value: "\(trip.events.count)")
                }
            }
            Section("Eventos") {
                if trip.events.isEmpty {
                    Text("Sin incidentes detectados.").foregroundStyle(.secondary)
                } else {
                    ForEach(trip.events) { event in
                        HStack {
                            Image(systemName: event.kind == .braking ? "arrow.down.right" : event.kind == .acceleration ? "arrow.up.right" : "arrow.turn.up.right")
                            Text(event.kind.rawValue)
                            if let direction = event.direction { Text("· \(direction)").foregroundStyle(.secondary) }
                            Spacer()
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Compartir estadísticas") { shareItem = IdentifiedString(value: trips.shareText(for: trip)) }
            }
        }
        .navigationTitle("Detalle del recorrido")
        .sheet(item: $shareItem) { ShareSheet(items: [$0.value]) }
    }
}
