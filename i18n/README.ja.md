<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### AMD Kria KV260 で Prophesee イベントカメラを使うための GUI 優先ワークスペース

</div>

## 概要

**Kria Metavision Lab** は、Prophesee AMD Kria KV260 starter kit を実用的なイベントビジョン環境として使うためのワークスペースです。PetaLinux の記録、ドライバ参照、デスクトップランチャー、診断スクリプト、カスタムカメラ GUI をまとめています。

目的は明快です。カメラを接続し、KV260 を起動し、デスクトップからビューアを開き、ライブイベントを確認し、分かりやすいファイル名で記録し、正常に終了できるようにします。

## カスタム GUI

| 機能 | 内容 |
| --- | --- |
| ライブ表示 | V4L2 イベントストリームを開き、HDMI デスクトップに表示します |
| 正常終了 | カメラデバイスを解放し、次回起動を安定させます |
| 記録 | 生のイベントバイト列を保存します |
| メタデータ | 各記録に JSON sidecar を書き出します |
| ランチャー | Matchbox/X11 デスクトップにメニュー項目を追加します |
| 復旧 | 固まったビューアやカメラ状態を整理します |

## 内容

| パス | 用途 |
| --- | --- |
| `scripts/` | ビューア、ランチャー、カメラスキャン、デスクトップ、RDP、復旧 |
| `references/` | 調査メモ、Prophesee リンク、セットアップ文書 |
| `fpga-projects/` | Prophesee KV260 FPGA project snapshot |
| `petalinux-projects/` | PetaLinux project snapshot とイメージ構築参考 |
| `linux-sensor-drivers/` | IMX636 と GenX320 の Linux ドライバ |
| `zynq-video-drivers/` | Zynq video pipeline driver |
| `event-vitisai-app/` | Vitis AI イベントデモの snapshot |

## クイックスタート

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

推奨リポジトリ名は `lachlanchen/kria-metavision-lab`、ホームページは `https://flow.lazying.art` です。公開前に、ローカルパスワード、プライベート IP、Prophesee アカウント由来のダウンロード、機械固有の設定を削除してください。
