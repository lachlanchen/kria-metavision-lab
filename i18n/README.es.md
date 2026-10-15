<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner — apps and four buddies](https://lazying.art/media/brand/lazyingart-intro.gif)](https://lazying.art)

# Kria Metavision Lab

### Un espacio de trabajo con GUI para usar cámaras de eventos Prophesee en AMD Kria KV260

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## Qué Es

**Kria Metavision Lab** es un espacio de trabajo práctico para convertir el kit Prophesee AMD Kria KV260 en una estación de visión basada en eventos. Reúne notas de PetaLinux, referencias de drivers, lanzadores de escritorio, diagnósticos y una GUI personalizada para la cámara.

El objetivo es directo: conectar la cámara, arrancar la KV260, abrir un elemento del escritorio, ver eventos en vivo, grabar datos con nombres previsibles y cerrar el visor limpiamente.

## GUI Personalizada

| Capacidad | Qué hace |
| --- | --- |
| Vista en vivo | Abre el flujo V4L2 y renderiza actividad de eventos en HDMI |
| Cierre limpio | Libera el dispositivo de cámara para el siguiente lanzamiento |
| Grabación | Guarda bytes de eventos crudos para análisis posterior |
| Metadatos | Escribe un sidecar JSON por captura |
| Lanzador | Añade un elemento simple al escritorio Matchbox/X11 |
| Recuperación | Limpia estados bloqueados del visor o la cámara |

## Contenido

| Ruta | Propósito |
| --- | --- |
| `scripts/` | Visor, lanzadores, escaneo de cámara, escritorio, RDP y recuperación |
| `references/` | Notas de investigación, enlaces Prophesee y documentación de despliegue |
| `fpga-projects/` | Snapshot del proyecto FPGA de Prophesee para KV260 |
| `petalinux-projects/` | Snapshot de PetaLinux y referencias para construir la imagen |
| `linux-sensor-drivers/` | Drivers Linux para IMX636 y GenX320 |
| `zynq-video-drivers/` | Drivers del pipeline de video Zynq |
| `event-vitisai-app/` | Snapshot del ejemplo Vitis AI de eventos |

## Inicio Rápido

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

El nombre recomendado es `lachlanchen/kria-metavision-lab` y la página principal es `https://flow.lazying.art`. Antes de publicar, limpia contraseñas locales, IP privadas, descargas de cuenta Prophesee y configuración específica de la máquina.

<!-- support:start -->
[![GitHub Sponsors](https://img.shields.io/badge/GitHub-Sponsors-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/lachlanchen)
[![LazyingArt Support](https://img.shields.io/badge/LazyingArt-Support-0EA5E9?style=for-the-badge)](https://chat.lazying.art/donate)
[![PayPal Support](https://img.shields.io/badge/PayPal-Support-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen)
[![Stripe Support](https://img.shields.io/badge/Stripe-Support-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400)
<!-- support:end -->
