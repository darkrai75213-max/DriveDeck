# DriveDeck

App iOS nativa (SwiftUI) que reproduce **toda la funcionalidad** de *CarDash: Videos e IPTV en auto* (v1.3.2, ID 6797764175, de Laigang Wang), con **todas las funciones premium desbloqueadas**, sin precios, sin paywall, sin analítica y sin servidores propios.

Es una implementación original: no usa el nombre, el logo ni los recursos de la app de referencia.

## Funcionalidad incluida

| Función de la referencia | Implementación en DriveDeck |
|---|---|
| Icono de la app | ✅ icono original de 1024×1024: silueta de hatchback deportivo genérico sobre degradado oscuro con halo rojo (sin logos de marca) |
| Salpicadero de inicio y diseños de vehículo/marca | ✅ pantalla **Inicio** oscura tipo cockpit, con anillo de velocidad, tarjetas, accesos rápidos y último viaje |
| Elección de coche al empezar | ✅ **SEAT Ibiza por defecto** (nickname "Mi Ibiza", diseño deportivo, acento rojo). Se puede cambiar en el Garaje y hay un atajo "Usar SEAT Ibiza". |
| "Mis datos" con icono del coche | ✅ pestaña **Mis datos** con insignia del Ibiza, ficha (marca/modelo, matrícula, diseño, color) y estadísticas |
| Listas IPTV M3U/M3U8 propias, navegación de canales, búsqueda, recarga | ✅ `Cast` → Listas IPTV (parser `#EXTINF`, `group-title`, URLs relativas) |
| Vídeos locales desde Fotos y desde Archivos | ✅ `Cast` → Vídeos locales (se copian al almacenamiento de la app) |
| Reproductor con AirPlay / pantalla externa | ✅ `AVPlayer` + selector de rutas de vídeo + render en `UIScreen` externa |
| Navegador integrado y enviar web a la pantalla del coche | ✅ `Cast` → Webs + `WKWebView` en pantalla externa |
| Favoritos de canales | ✅ botón de estrella |
| Grabación automática de viajes, velocidad/distancia/duración | ✅ `Drive` (CoreLocation en segundo plano) |
| Puntuación, aceleraciones, frenadas y curvas | ✅ `Drive` (CoreMotion) |
| Reproducción de ruta, mapa de territorio, compartir | ✅ MapKit + hoja de compartir |
| Millas o kilómetros | ✅ interruptor en `Drive` |
| Widgets de pantalla de inicio: foto/fecha/cuenta atrás/matrícula/diseños | ✅ extensión WidgetKit con estilos reloj, fecha, cuenta atrás, matrícula y marca (configurables en el propio widget) |
| Sonidos de conectar, desconectar y llegar + automatizaciones | ✅ `Sonidos` + App Intents para Atajos + detección de cambio de ruta de audio |
| Todo premium | ✅ sin límites, sin compras, sin suscripción |

### Limitaciones reales de iOS (importante)

Ninguna app firmada con un Apple ID normal puede:

1. **Accionar el interruptor de duplicado de pantalla del Centro de Control** desde código. DriveDeck ofrece el selector nativo de AirPlay (un toque) y renderiza directamente en una pantalla externa conectada. No es un jailbreak tweak.
2. **Inyectar vídeo arbitrario en la pantalla nativa de CarPlay**. Apple solo permite las apps de CarPlay autorizadas. La vía equivalente es AirPlay a una caja/head unit compatible, o duplicar desde el Centro de Control del iPhone.
3. **Compartir datos app ↔ widget mediante App Groups con firma gratuita**. Por eso los widgets se configuran desde el propio widget (iOS 17+). Con una cuenta de desarrollador de pago se puede añadir sincronización.
4. La renovación de la firma gratuita caduca a los **7 días**; hay que renovarla desde Sideloadly/AltStore (o usar TestFlight con cuenta de pago).

El vídeo está pensado para usarse **con el coche aparcado**.

## Cómo compilar el IPA (necesita macOS; GitHub lo da gratis con un repo público)

1. Crea un repositorio **público** en GitHub y sube esta carpeta (GitHub Desktop sirve).
2. En el repo: **Actions → Build IPA (unsigned, para sideload) → Run workflow**.
3. Cuando termine (5–10 min), descarga el artefacto **DriveDeck-IPA** y descomprímelo para obtener `DriveDeck.ipa`.

También puedes compilarlo en tu Mac con:

```bash
xcodebuild -project DriveDeck.xcodeproj -scheme DriveDeck \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build
```

## Cómo instalarlo en tu iPhone desde Windows

1. Instala **iTunes** (de Apple, no de Microsoft Store) y **Sideloadly** (`sideloadly.io`).
2. Conecta el iPhone por USB y pulsa «Confiar» si aparece el aviso.
3. Abre Sideloadly:
   - **IPA**: selecciona `DriveDeck.ipa`.
   - **Apple ID**: tu ID de Apple. Si tienes doble factor, genera una **contraseña específica de app** en `appleid.apple.com` y usa esa.
   - Marca la opción para conservar datos entre firmas si quieres no perder viajes al renovar.
   - Pulsa **Start** e introduce la contraseña cuando te la pida iTunes/Apple.
4. En el iPhone: **Ajustes → General → VPN y gestión de dispositivos → confía en tu certificado de desarrollador**.
5. Abre DriveDeck.

### Permisos que debes conceder

- **Ubicación → Siempre** (necesario para grabar viajes en segundo plano).
- **Movimiento y orientación** (para la puntuación de conducción).
- **Fotos** si importas vídeos desde la galería.
- **Red local / AirPlay** para enviar vídeo a la pantalla del coche.

### Renovar la firma

Cada 7 días, vuelve a conectar el iPhone a Sideloadly y pulsa **Start** otra vez. Si usas la opción «conservar datos», tus viajes y listas se mantienen. Para una firma de un año sin renovación semanal necesitas la cuenta de desarrollador (99 USD/año) y TestFlight.

## Guías rápidas

- **Añadir IPTV**: Cast → “Añadir lista M3U / M3U8” → pega tu URL → los canales aparecen en la lista. La app no incluye canales.
- **Ver vídeo en el coche**: reproduce el vídeo, pulsa el botón de AirPlay en la fila “Reproduciendo” y elige tu receptor. También puedes abrir el Centro de Control → Duplicado de pantalla.
- **Widgets**: mantén pulsado el widget → Editar widget → elige estilo/diseño/color/matrícula/fecha.
- **Sonidos**: Sonidos → elige los tres sonidos o importa los tuyos → crea una automatización en la app Atajos con “Reproducir sonido de conexión/llegada”.

## Estructura

```
DriveDeck.xcodeproj/project.pbxproj
DriveDeck/DriveDeckApp.swift       lifecycle, pestañas, tema
DriveDeck/MediaFeature.swift      IPTV, vídeos, webs, AirPlay, pantalla externa
DriveDeck/DriveFeature.swift      GPS, acelerómetro, viajes, mapas
DriveDeck/SoundsFeature.swift     sonidos + App Intents
DriveDeck/VehicleFeature.swift    garaje, onboarding y salpicadero cockpit
DriveDeck/WidgetsGuideView.swift  guía de widgets
DriveDeckWidget/DriveDeckWidget.swift  WidgetKit + configuración
```
