<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### 面向 AMD Kria KV260 上 Prophesee 事件相機的 GUI 優先工作區

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## 專案簡介

**Kria Metavision Lab** 是一個實際可用的 KV260 事件視覺實驗工作區。它把 Prophesee starter kit 的板端 bring-up、PetaLinux 記錄、驅動參考、桌面啟動器、相機診斷和自訂 GUI 放在同一個倉庫中。

目標很直接：接上事件相機，啟動 KV260，點擊桌面選單，看到即時事件，按可控檔名錄製資料，並且能正常關閉查看器。

## 自訂 GUI

| 功能 | 說明 |
| --- | --- |
| 即時預覽 | 打開 V4L2 事件流，並在 HDMI 桌面上顯示事件活動 |
| 正常關閉 | 釋放相機設備，避免下一次啟動失敗 |
| 錄製 | 保存原始事件位元組，便於後續分析 |
| 元資料 | 為每次錄製寫入 JSON sidecar |
| 桌面啟動器 | 在 Matchbox/X11 桌面中加入簡單選單項 |
| 恢復腳本 | 清理卡住的查看器或相機狀態 |

## 倉庫內容

| 路徑 | 用途 |
| --- | --- |
| `scripts/` | 查看器、啟動器、相機掃描、桌面、RDP 和恢復腳本 |
| `references/` | 研究記錄、部署筆記、Prophesee 連結和 GUI 文件 |
| `fpga-projects/` | Prophesee KV260 FPGA 專案快照 |
| `petalinux-projects/` | PetaLinux 專案快照和映像構建參考 |
| `linux-sensor-drivers/` | IMX636 和 GenX320 Linux 驅動原始碼 |
| `zynq-video-drivers/` | Kit 使用的 Zynq video pipeline 驅動原始碼 |
| `event-vitisai-app/` | LogicTronix / Prophesee / AMD Vitis AI 示例快照 |

## 快速開始

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub 資訊

倉庫名建議使用 `lachlanchen/kria-metavision-lab`，首頁使用 `https://flow.lazying.art`。公開發布前請清理本地密碼、私有 IP、Prophesee 帳號下載和機器專屬配置。
