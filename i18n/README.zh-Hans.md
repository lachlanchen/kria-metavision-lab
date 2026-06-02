<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### 面向 AMD Kria KV260 上 Prophesee 事件相机的 GUI 优先工作区

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## 项目简介

**Kria Metavision Lab** 是一个实际可用的 KV260 事件视觉实验工作区。它把 Prophesee starter kit 的板端 bring-up、PetaLinux 记录、驱动参考、桌面启动器、相机诊断和自定义 GUI 放在同一个仓库中。

目标很直接：接上事件相机，启动 KV260，点击桌面菜单，看到实时事件，按可控文件名录制数据，并且能正常关闭查看器。

## 自定义 GUI

仓库的核心是为 PetaLinux 本地桌面准备的 KV260 事件相机应用：

| 功能 | 说明 |
| --- | --- |
| 实时预览 | 打开 V4L2 事件流，并在 HDMI 桌面上显示事件活动 |
| 正常关闭 | 释放相机设备，避免下一次启动失败 |
| 录制 | 保存原始事件字节，便于后续分析 |
| 元数据 | 为每次录制写入 JSON sidecar |
| 桌面启动器 | 在 Matchbox/X11 桌面中添加简单菜单项 |
| 恢复脚本 | 清理卡住的查看器或相机状态 |

## 仓库内容

| 路径 | 用途 |
| --- | --- |
| `scripts/` | 查看器、启动器、相机扫描、桌面、RDP 和恢复脚本 |
| `references/` | 研究记录、部署笔记、Prophesee 链接和 GUI 文档 |
| `fpga-projects/` | Prophesee KV260 FPGA 项目快照 |
| `petalinux-projects/` | PetaLinux 项目快照和镜像构建参考 |
| `linux-sensor-drivers/` | IMX636 和 GenX320 Linux 驱动源码 |
| `zynq-video-drivers/` | Kit 使用的 Zynq video pipeline 驱动源码 |
| `event-vitisai-app/` | LogicTronix / Prophesee / AMD Vitis AI 示例快照 |

## 快速开始

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub 信息

仓库名建议使用 `lachlanchen/kria-metavision-lab`，主页使用 `https://flow.lazying.art`。公开发布前请清理本地密码、私有 IP、Prophesee 账号下载和机器专属配置。
