import SwiftUI

struct WidgetsGuideView: View {
    private let steps: [(String, String)] = [
        ("1", "Mantén pulsado un espacio vacío de la pantalla de inicio hasta que los iconos bailen."),
        ("2", "Pulsa el botón «+» de la esquina superior izquierda."),
        ("3", "Busca DriveDeck y elige el tamaño pequeño, mediano o grande."),
        ("4", "Mantén pulsado el widget y elige «Editar widget» para seleccionar estilo, diseño, color, matrícula, título y cuenta atrás.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)

                    Text("Widgets de pantalla de inicio")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)

                    Text("La app incluye una extensión WidgetKit con cinco estilos: reloj, fecha, cuenta atrás, matrícula y diseño de marca. Cada widget se configura directamente desde la pantalla de inicio, igual que los widgets nativos.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(steps, id: \.0) { number, text in
                            HStack(alignment: .top, spacing: 12) {
                                Text(number)
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Color.accentColor, in: Circle())
                                Text(text)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Estilos disponibles", systemImage: "sparkles").font(.headline)
                        Text("• Reloj: hora actual y fecha.\n• Fecha: día destacado con diseño de vehículo.\n• Cuenta atrás: días, horas y minutos hasta la fecha que elijas.\n• Matrícula: placa personalizable con estilo de país.\n• Marca: diseño deportivo, neutro, lujo o eléctrico.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nota sobre la firma gratuita", systemImage: "info.circle").font(.headline)
                        Text("Con un Apple ID normal, iOS no permite compartir datos entre la app y el widget mediante App Groups. Por eso la configuración se hace en el propio widget. Si más adelante usas una cuenta de desarrollador de pago, se puede añadir sincronización completa desde la app.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Widgets")
        }
    }
}
