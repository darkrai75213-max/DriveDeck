import WidgetKit
import SwiftUI
import AppIntents
import PhotosUI
import OSLog

// MARK: - Opciones configurables desde el widget

enum WidgetStyle: String, AppEnum {
    case clock, date, countdown, plate, brand, photo

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Estilo")

    static let caseDisplayRepresentations: [WidgetStyle: DisplayRepresentation] = [
        .clock: DisplayRepresentation(title: "Reloj"),
        .date: DisplayRepresentation(title: "Fecha"),
        .countdown: DisplayRepresentation(title: "Cuenta atrás"),
        .plate: DisplayRepresentation(title: "Matrícula"),
        .brand: DisplayRepresentation(title: "Diseño de marca"),
        .photo: DisplayRepresentation(title: "Foto de mi galería")
    ]
}

enum BrandTheme: String, AppEnum {
    case neutral, sport, luxury, electric

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Diseño")

    static let caseDisplayRepresentations: [BrandTheme: DisplayRepresentation] = [
        .neutral: DisplayRepresentation(title: "Neutro"),
        .sport: DisplayRepresentation(title: "Deportivo"),
        .luxury: DisplayRepresentation(title: "Lujo"),
        .electric: DisplayRepresentation(title: "Eléctrico")
    ]
}

enum WidgetTint: String, AppEnum {
    case blue, orange, green, purple, red

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Color")

    static let caseDisplayRepresentations: [WidgetTint: DisplayRepresentation] = [
        .blue: DisplayRepresentation(title: "Azul"),
        .orange: DisplayRepresentation(title: "Naranja"),
        .green: DisplayRepresentation(title: "Verde"),
        .purple: DisplayRepresentation(title: "Morado"),
        .red: DisplayRepresentation(title: "Rojo")
    ]

    var color: Color {
        switch self {
        case .blue: return .blue
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .red: return .red
        }
    }
}

struct WidgetConfigIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configurar DriveDeck"
    static let description: IntentDescription? = IntentDescription("Elige el estilo y el diseño del widget.")

    @Parameter(title: "Estilo")
    var style: WidgetStyle?

    @Parameter(title: "Diseño")
    var brand: BrandTheme?

    @Parameter(title: "Color")
    var tint: WidgetTint?

    @Parameter(title: "Matrícula")
    var plate: String?

    @Parameter(title: "Título")
    var title: String?

    @Parameter(title: "Cuenta atrás")
    var countdown: Date?

    @Parameter(
        title: "Foto",
        description: "Elige una imagen de tu galería",
        supportedTypeIdentifiers: ["public.image"]
    )
    var photo: IntentFile?

    // WidgetConfigurationIntent exige parámetros opcionales. Los valores por
    // defecto se resuelven aquí para que el widget nunca quede vacío.
    init() {
        style = .clock
        brand = .neutral
        tint = .blue
        plate = "ABC 123"
        title = "DriveDeck"
        countdown = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ?? Date().addingTimeInterval(86_400)
    }

    var resolvedStyle: WidgetStyle { style ?? .clock }
    var resolvedBrand: BrandTheme { brand ?? .neutral }
    var resolvedTint: WidgetTint { tint ?? .blue }
    var resolvedPlate: String {
        let value = plate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "ABC 123" : value
    }
    var resolvedTitle: String {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "DriveDeck" : value
    }
    var resolvedCountdown: Date { countdown ?? Date().addingTimeInterval(86_400) }
}

// MARK: - Timeline

struct WidgetEntry: TimelineEntry {
    let date: Date
    let config: WidgetConfigIntent
    let photo: UIImage?
}

private enum WidgetPhotoLoader {
    static func load(_ file: IntentFile?) -> UIImage? {
        guard let file else { return nil }
        if let url = file.fileURL, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: UIImage?
        Task {
            defer { semaphore.signal() }
            do {
                let data = try await file.data
                result = UIImage(data: data)
            } catch {
                os_log("DriveDeck widget photo error: %{public}@", log: .default, type: .error, String(describing: error))
            }
        }
        semaphore.wait()
        return result
    }
}

struct WidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), config: WidgetConfigIntent(), photo: nil)
    }

    func snapshot(for configuration: WidgetConfigIntent, in context: Context) async -> WidgetEntry {
        WidgetEntry(date: Date(), config: configuration, photo: WidgetPhotoLoader.load(configuration.photo))
    }

    func timeline(for configuration: WidgetConfigIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let now = Date()
        let photo = WidgetPhotoLoader.load(configuration.photo)
        let entries = stride(from: 0, to: 4, by: 1).map { index in
            WidgetEntry(date: now.addingTimeInterval(Double(index) * 900), config: configuration, photo: photo)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(900)))
    }
}

// MARK: - Vistas

struct WidgetEntryView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.config.resolvedStyle {
            case .clock:
                ClockWidget(entry: entry)
            case .date:
                DateWidget(entry: entry)
            case .countdown:
                CountdownWidget(entry: entry)
            case .plate:
                PlateWidget(entry: entry)
            case .brand:
                BrandWidget(entry: entry)
            case .photo:
                PhotoWidget(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [entry.config.resolvedTint.color.opacity(0.28), Color.black.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct ClockWidget: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: familySize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack {
                Image(systemName: "car.fill")
                Text(entry.config.resolvedTitle)
                    .font(.caption2)
            }
            .foregroundStyle(entry.config.resolvedTint.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var familySize: CGFloat { 34 }
}

struct DateWidget: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.display.fill")
                .font(.title2)
                .foregroundStyle(entry.config.resolvedTint.color)
            Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline.bold())
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            Text(entry.config.resolvedTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CountdownWidget: View {
    let entry: WidgetEntry

    private var components: DateComponents {
        let calendar = Calendar.current
        let seconds = max(0, Int(entry.config.resolvedCountdown.timeIntervalSince(entry.date)))
        return calendar.dateComponents([.day, .hour, .minute], from: Date(), to: Date().addingTimeInterval(TimeInterval(seconds)))
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(entry.config.resolvedTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 10) {
                CountBox(value: components.day ?? 0, label: "d")
                CountBox(value: components.hour ?? 0, label: "h")
                CountBox(value: components.minute ?? 0, label: "m")
            }
            Spacer(minLength: 0)
            Text(entry.config.resolvedCountdown.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CountBox: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 42)
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PlateWidget: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text(entry.config.resolvedPlate)
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(entry.config.resolvedTint.color, lineWidth: 3)
                )
                .foregroundStyle(.black)
            Text(entry.config.resolvedTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BrandWidget: View {
    let entry: WidgetEntry

    private var subtitle: String {
        switch entry.config.resolvedBrand {
        case .neutral: return "Everyday"
        case .sport: return "Performance"
        case .luxury: return "Premium"
        case .electric: return "Electric"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.config.resolvedBrand == .electric ? "bolt.car.fill" : "car.fill")
                    .font(.largeTitle)
                    .foregroundStyle(entry.config.resolvedTint.color)
                Spacer()
                if entry.config.resolvedBrand == .sport {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(entry.config.resolvedTitle)
                .font(.headline.bold())
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PhotoWidget: View {
    let entry: WidgetEntry

    var body: some View {
        ZStack {
            if let image = entry.photo {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                    Text("Elige una foto al editar el widget")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            Text(entry.config.resolvedTitle)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(6)
        }
    }
}

@main
struct DriveDeckWidget: Widget {
    let kind: String = "DriveDeckWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetConfigIntent.self,
            provider: WidgetProvider()
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DriveDeck")
        .description("Reloj, fecha, cuenta atrás, matrícula, diseños de coche y tus fotos.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
