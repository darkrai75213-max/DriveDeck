"""Comprobaciones estáticas del proyecto. No sustituye a xcodebuild."""
import os
import re
import sys
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
errors = []
warnings = []

# 1. Todos los ficheros referenciados en el pbxproj existen
pbx = (ROOT / "DriveDeck.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
refs = re.findall(r"path = ([^;]+); sourceTree", pbx)
for ref in refs:
    if ref.endswith((".app", ".appex")):
        continue  # productos generados por xcodebuild
    if ref.startswith(("DriveDeck", "Info.plist")):
        for candidate in [ROOT / ref, ROOT / "DriveDeck" / ref, ROOT / "DriveDeckWidget" / ref]:
            if candidate.exists():
                break
        else:
            errors.append(f"PBXProject: falta el archivo referenciado {ref}")

# 2. Llaves y paréntesis balanceados en pbxproj
for opening, closing in [("{", "}"), ("(", ")")]:
    if pbx.count(opening) != pbx.count(closing):
        errors.append(
            f"pbxproj desbalanceado: {opening}={pbx.count(opening)} {closing}={pbx.count(closing)}"
        )

# 3. Todos los UUIDs usados están definidos
defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", pbx, re.M))
used = set(re.findall(r"\b([0-9A-F]{24})\b", pbx))
missing = used - defined
if missing:
    errors.append(f"UUIDs sin definir en pbxproj: {sorted(missing)}")

# 4. Plists válidos
for plist in ROOT.rglob("*.plist"):
    try:
        with plist.open("rb") as fh:
            plistlib.load(fh)
    except Exception as exc:
        errors.append(f"Plist inválido {plist}: {exc}")
for entitlements in ROOT.rglob("*.entitlements"):
    try:
        with entitlements.open("rb") as fh:
            plistlib.load(fh)
    except Exception as exc:
        errors.append(f"Entitlements inválidos {entitlements}: {exc}")

# 5. Equilibrio básico de llaves en Swift (ignorando strings y comentarios simples)
def strip_noise(text):
    # Primero las cadenas: si se hace antes el comentario, una URL "https://…"
    # dentro de un string se confunde con el inicio de un comentario.
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"//[^\n]*", "", text)
    return text

for swift in ROOT.rglob("*.swift"):
    text = strip_noise(swift.read_text(encoding="utf-8"))
    if text.count("{") != text.count("}"):
        warnings.append(
            f"{swift.relative_to(ROOT)}: llaves {text.count('{')} vs {text.count('}')}"
        )

# 6. Referencias cruzadas de tipos usados en el proyecto
sources = "\n".join(p.read_text(encoding="utf-8") for p in ROOT.rglob("*.swift"))
expected_types = [
    "MediaStore", "TripStore", "SoundManager", "CastView", "DriveView",
    "SoundsView", "WidgetsGuideView", "WidgetConfigIntent", "DriveDeckWidget",
    "ExternalDisplayManager", "M3UParser", "AppIntentConfiguration",
    "VehicleStore", "GarageSetupView", "HomeView", "SpeedRing",
    "MyDataView", "VehicleBadge", "SEAT Ibiza",
]
for name in expected_types:
    if name not in sources:
        errors.append(f"Falta la definición/uso de {name}")

# 7. Info.plist con permisos clave
app_plist = plistlib.loads((ROOT / "DriveDeck" / "Info.plist").read_bytes())
for key in ["UIBackgroundModes", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSMotionUsageDescription"]:
    if key not in app_plist:
        errors.append(f"Falta {key} en Info.plist")

# 8. CFBundleExecutable presente en ambos plists (Sideloadly lo exige)
for rel in ["DriveDeck/Info.plist", "DriveDeckWidget/Info.plist"]:
    data = plistlib.loads((ROOT / rel).read_bytes())
    exe = data.get("CFBundleExecutable")
    if not exe:
        errors.append(f"Falta CFBundleExecutable en {rel}")

# 9. Icono de la app
icon = ROOT / "DriveDeck" / "Assets.xcassets" / "AppIcon.appiconset" / "Icon-1024.png"
if not icon.exists() or icon.stat().st_size < 10_000:
    errors.append("Falta el icono Icon-1024.png")
for needed in ["Icon-60@3x.png", "Icon-60@2x.png"]:
    if not (icon.parent / needed).exists():
        errors.append(f"Falta el tamaño de icono {needed}")
if "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" not in pbx:
    errors.append("Falta ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon en el pbxproj")

# Resultado
print(f"Revisados {len(list(ROOT.rglob('*.swift')))} archivos Swift, {len(refs)} referencias de proyecto.")
for warning in warnings:
    print("AVISO:", warning)
for error in errors:
    print("ERROR:", error)
if errors:
    sys.exit(1)
print("OK: validación estática superada (la compilación real requiere macOS/Xcode).")
