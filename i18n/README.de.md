<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### Ein GUI-orientierter Arbeitsbereich für Prophesee Event-Kameras auf AMD Kria KV260

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## Überblick

**Kria Metavision Lab** ist ein praktischer Arbeitsbereich, um das Prophesee AMD Kria KV260 Starter Kit als Event-Vision-Station zu nutzen. Das Repository bündelt PetaLinux-Notizen, Treiberreferenzen, Desktop-Launcher, Diagnosewerkzeuge und eine eigene Kamera-GUI.

Das Ziel ist einfach: Kamera anschließen, KV260 booten, Desktop-Eintrag öffnen, Live-Events sehen, Daten mit vorhersehbaren Dateinamen aufzeichnen und den Viewer sauber schließen.

## Eigene GUI

| Fähigkeit | Beschreibung |
| --- | --- |
| Live-Vorschau | Öffnet den V4L2-Eventstream und zeigt Aktivität auf HDMI |
| Sauberes Schließen | Gibt das Kameragerät für den nächsten Start frei |
| Aufnahme | Speichert rohe Event-Bytes für spätere Analyse |
| Metadaten | Schreibt eine JSON-Sidecar-Datei pro Aufnahme |
| Desktop-Launcher | Fügt einen einfachen Eintrag in Matchbox/X11 hinzu |
| Wiederherstellung | Bereinigt blockierte Viewer- oder Kamerazustände |

## Inhalt

| Pfad | Zweck |
| --- | --- |
| `scripts/` | Viewer, Launcher, Kamerascan, Desktop, RDP und Recovery |
| `references/` | Forschungsnotizen, Prophesee-Links und Deployment-Dokumente |
| `fpga-projects/` | Snapshot des Prophesee FPGA-Projekts für KV260 |
| `petalinux-projects/` | PetaLinux-Snapshot und Image-Build-Referenzen |
| `linux-sensor-drivers/` | Linux-Treiber für IMX636 und GenX320 |
| `zynq-video-drivers/` | Zynq Video-Pipeline-Treiber |
| `event-vitisai-app/` | Snapshot der Vitis AI Event-Demo |

## Schnellstart

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

Der empfohlene Name ist `lachlanchen/kria-metavision-lab`, die Homepage ist `https://flow.lazying.art`. Entfernen Sie vor einer öffentlichen Veröffentlichung lokale Passwörter, private IPs, Prophesee-Konto-Downloads und maschinenspezifische Konfiguration.
