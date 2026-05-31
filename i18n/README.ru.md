<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### GUI-ориентированная рабочая среда для камер Prophesee на AMD Kria KV260

</div>

## О Проекте

**Kria Metavision Lab** - практическая рабочая среда для превращения Prophesee AMD Kria KV260 starter kit в станцию для экспериментов с event-based vision. Репозиторий объединяет заметки PetaLinux, ссылки на драйверы, desktop launchers, диагностику и собственный GUI для камеры.

Цель проста: подключить камеру, загрузить KV260, открыть пункт меню рабочего стола, увидеть live events, записать данные с понятными именами файлов и корректно закрыть viewer.

## Пользовательский GUI

| Возможность | Что делает |
| --- | --- |
| Live preview | Открывает V4L2 event stream и показывает активность на HDMI |
| Clean close | Освобождает устройство камеры для следующего запуска |
| Recording | Сохраняет сырые байты событий для анализа |
| Metadata | Пишет JSON sidecar для каждой записи |
| Desktop launcher | Добавляет простой пункт меню в Matchbox/X11 |
| Recovery | Очищает зависшие состояния viewer или камеры |

## Содержимое

| Путь | Назначение |
| --- | --- |
| `scripts/` | Viewer, launchers, camera scan, desktop, RDP и recovery |
| `references/` | Исследовательские заметки, ссылки Prophesee и документация |
| `fpga-projects/` | Snapshot FPGA-проекта Prophesee для KV260 |
| `petalinux-projects/` | Snapshot PetaLinux и ссылки для сборки image |
| `linux-sensor-drivers/` | Linux-драйверы IMX636 и GenX320 |
| `zynq-video-drivers/` | Драйверы Zynq video pipeline |
| `event-vitisai-app/` | Snapshot Vitis AI event demo |

## Быстрый Старт

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

Рекомендуемое имя репозитория: `lachlanchen/kria-metavision-lab`, homepage: `https://flow.lazying.art`. Перед публикацией удалите локальные пароли, приватные IP, загрузки из аккаунта Prophesee и настройки конкретной машины.
