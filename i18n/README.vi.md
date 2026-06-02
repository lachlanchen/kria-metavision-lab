<div align="center">

[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# Kria Metavision Lab

### Không gian làm việc ưu tiên GUI cho camera sự kiện Prophesee trên AMD Kria KV260

<sub>Powered by [AgInTi Flow](https://flow.lazying.art), created by LazyingArt LLC.</sub>

</div>

## Giới Thiệu

**Kria Metavision Lab** là một không gian làm việc thực tế để biến bộ Prophesee AMD Kria KV260 thành trạm thử nghiệm thị giác sự kiện. Kho này gom ghi chú PetaLinux, tài liệu driver, launcher desktop, công cụ chẩn đoán và GUI camera tùy chỉnh.

Mục tiêu rất rõ: cắm camera, khởi động KV260, mở từ menu desktop, xem sự kiện trực tiếp, ghi dữ liệu với tên file dễ kiểm soát và đóng viewer sạch sẽ.

## GUI Tùy Chỉnh

| Khả năng | Mô tả |
| --- | --- |
| Xem trực tiếp | Mở luồng V4L2 và hiển thị hoạt động sự kiện trên HDMI |
| Đóng sạch | Nhả thiết bị camera để lần mở sau hoạt động bình thường |
| Ghi dữ liệu | Lưu byte sự kiện thô để phân tích |
| Metadata | Ghi file JSON sidecar cho từng lần capture |
| Launcher | Thêm mục menu cho desktop Matchbox/X11 |
| Khôi phục | Dọn trạng thái viewer hoặc camera bị kẹt |

## Nội Dung

| Đường dẫn | Mục đích |
| --- | --- |
| `scripts/` | Viewer, launcher, quét camera, desktop, RDP và khôi phục |
| `references/` | Ghi chú nghiên cứu, liên kết Prophesee và tài liệu triển khai |
| `fpga-projects/` | Snapshot dự án FPGA Prophesee cho KV260 |
| `petalinux-projects/` | Snapshot PetaLinux và tham khảo build image |
| `linux-sensor-drivers/` | Driver Linux cho IMX636 và GenX320 |
| `zynq-video-drivers/` | Driver pipeline video Zynq |
| `event-vitisai-app/` | Snapshot demo Vitis AI sự kiện |

## Bắt Đầu Nhanh

```sh
cd ~/Projects/kria-metavision-lab
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --start
./scripts/kv260-install-prophesee-desktop.sh --install
```

## GitHub

Tên kho được đề xuất là `lachlanchen/kria-metavision-lab`, homepage là `https://flow.lazying.art`. Trước khi công khai, hãy xóa mật khẩu cục bộ, IP riêng, tải xuống từ tài khoản Prophesee và cấu hình riêng của máy.
