<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### Un espace de travail orienté GUI pour les caméras événementielles Prophesee sur AMD Kria KV260

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## Présentation

**Kria Metavision Lab** est un espace de travail pratique pour transformer le kit Prophesee AMD Kria KV260 en station de vision événementielle. Il rassemble les notes PetaLinux, les références de pilotes, les lanceurs de bureau, les diagnostics et une interface personnalisée pour la caméra.

Le but est simple : brancher la caméra, démarrer la KV260, ouvrir un élément du bureau, voir les événements en direct, enregistrer les données avec des noms prévisibles et fermer le visualiseur proprement.

## Interface Personnalisée

| Fonction | Rôle |
| --- | --- |
| Aperçu live | Ouvre le flux V4L2 et affiche l'activité événementielle sur HDMI |
| Fermeture propre | Libère la caméra pour le lancement suivant |
| Enregistrement | Sauvegarde les octets bruts des événements |
| Métadonnées | Écrit un fichier JSON associé à chaque capture |
| Lanceur bureau | Ajoute un menu simple dans Matchbox/X11 |
| Récupération | Nettoie les états bloqués du visualiseur ou de la caméra |

## Contenu

| Chemin | Utilité |
| --- | --- |
| `scripts/` | Visualiseur, lanceurs, scan caméra, bureau, RDP et récupération |
| `references/` | Notes de recherche, liens Prophesee et documentation |
| `fpga-projects/` | Snapshot du projet FPGA Prophesee pour KV260 |
| `petalinux-projects/` | Snapshot PetaLinux et références de build image |
| `linux-sensor-drivers/` | Pilotes Linux IMX636 et GenX320 |
| `zynq-video-drivers/` | Pilotes du pipeline vidéo Zynq |
| `event-vitisai-app/` | Snapshot de l'exemple Vitis AI événementiel |

## Démarrage Rapide

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

Le nom recommandé est `lachlanchen/kria-metavision-lab` et la page d'accueil est `https://flow.lazying.art`. Avant publication, supprimez les mots de passe locaux, IP privées, téléchargements Prophesee authentifiés et réglages propres à la machine.
