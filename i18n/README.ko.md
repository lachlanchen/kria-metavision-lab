<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### AMD Kria KV260에서 Prophesee 이벤트 카메라를 쓰기 위한 GUI 중심 작업 공간

</div>

## 소개

**Kria Metavision Lab**은 Prophesee AMD Kria KV260 starter kit를 실제 이벤트 비전 워크스테이션처럼 쓰기 위한 작업 공간입니다. PetaLinux 기록, 드라이버 참고 자료, 데스크톱 런처, 진단 스크립트, 커스텀 카메라 GUI를 한 곳에 모았습니다.

목표는 단순합니다. 카메라를 연결하고, KV260을 부팅하고, 데스크톱 메뉴에서 뷰어를 열고, 실시간 이벤트를 보고, 예측 가능한 파일명으로 기록하고, 깨끗하게 종료하는 것입니다.

## 커스텀 GUI

| 기능 | 설명 |
| --- | --- |
| 라이브 미리보기 | V4L2 이벤트 스트림을 열고 HDMI 데스크톱에 표시합니다 |
| 깨끗한 종료 | 카메라 장치를 해제해 다음 실행을 안정화합니다 |
| 기록 | 원시 이벤트 바이트를 저장합니다 |
| 메타데이터 | 각 캡처 옆에 JSON sidecar를 씁니다 |
| 데스크톱 런처 | Matchbox/X11 메뉴 항목을 추가합니다 |
| 복구 | 멈춘 뷰어 또는 카메라 상태를 정리합니다 |

## 구성

| 경로 | 목적 |
| --- | --- |
| `scripts/` | 뷰어, 런처, 카메라 스캔, 데스크톱, RDP, 복구 |
| `references/` | 연구 노트, Prophesee 링크, 배포 문서 |
| `fpga-projects/` | Prophesee KV260 FPGA project snapshot |
| `petalinux-projects/` | PetaLinux project snapshot 및 이미지 빌드 참고 |
| `linux-sensor-drivers/` | IMX636 및 GenX320 Linux 드라이버 |
| `zynq-video-drivers/` | Zynq video pipeline 드라이버 |
| `event-vitisai-app/` | Vitis AI 이벤트 데모 snapshot |

## 빠른 시작

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

권장 저장소 이름은 `lachlanchen/kria-metavision-lab`이고 홈페이지는 `https://flow.lazying.art`입니다. 공개 전에 로컬 비밀번호, 사설 IP, Prophesee 계정 다운로드, 장비별 설정을 제거하세요.
