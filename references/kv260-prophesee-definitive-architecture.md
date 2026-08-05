# KV260 Prophesee 相机确定性架构与诊断准则

更新日期：2026-08-05

## 已确认结论

这台 KV260 上的 Prophesee IMX636 相机长期正常工作。本次真实重启后，原生 Metavision HAL 再次完成设备发现、打开与事件传输，并报告 `CD Events:3544`。因此不能用静态场景下 `v4l2-ctl --stream-count=N` 等不到 N 个缓冲来判断相机损坏。

事件相机是数据驱动设备：亮度对数变化触发事件，静态场景可以在较长时间内不产生新 payload。固定缓冲数量测试可能一直等待，这是正常语义，不是帧率为零。

## 硬件与数据路径

```text
IMX636 sensor
  -> MIPI CSI-2 receiver
  -> AXI tkeep handler
  -> event stream smart tracker
  -> ps_host_if / psee-dma
  -> /dev/video0
  -> native Metavision HAL or custom V4L2 application
```

关键节点：

| 组件 | 当前节点或标识 |
|---|---|
| Sensor | `imx636 6-003c`, normally `/dev/v4l-subdev3` |
| Media graph | `/dev/media0` |
| Event stream | `/dev/video0` |
| FPGA application | `prophesee-kv260-imx636` |
| Resolution | `1280 x 720` |
| Native runtime | Metavision 5.0.0 / `hal_plugin_prophesee` |

## PSE1 与 PSE2

同一 EVT2.1 信息可以由两种 64-bit V4L2 布局承载：

- `PSE2`：native EVT2.1 layout，事件类型和坐标字段位于高 32 bits。
- `PSE1`：EVT2.1 legacy layout，事件字段位于低 32 bits，vector mask 位于高 32 bits。

原生 Metavision HAL 可以处理重启后枚举出的 `PSE1`。仓库自定义 Python decoder 当前主要按 `PSE2` 解释，因此自定义 GUI/API 应在后续改为查询实际 pixel format 或自动识别两种布局，不能把 `PSE1` 直接标记为 `PSE2`。

## 三条软件路径

### Native Metavision Viewer

用于硬件/HAL smoke test。可靠启动条件：

```sh
DISPLAY=:0 \
XAUTHORITY=/home/petalinux/.Xauthority \
V4L2_SENSOR_PATH=/dev/v4l-subdev3 \
/usr/bin/metavision_viewer
```

成功标志：

```text
V4l2 Discovery with great success +1
Camera has been opened successfully.
V4l2DataTransfer - start_impl()
V4l2DataTransfer - run_impl()
```

不要在 `petalinux` 用户无权限时强制设置 `V4L2_HEAP=reserved`。本机 `/dev/dma_heap/reserved` 重启后为 root-only；不指定 heap 时 HAL 可以使用兼容后端正常工作。

### Custom GTK Event Camera

`scripts/kv260-event-camera-app.py` 直接 mmap `/dev/video0`。采集热路径为：

```text
select -> DQBUF -> copy payload -> QBUF immediately
       -> bounded recording queue
       -> bounded newest-payload preview queue
```

预览慢不会阻塞原始写盘。静态场景下 GUI 保留最后的 event-time surface，而不是把画面立即清空。

### Headless Recording API

`scripts/kv260-event-camera-api.py` 复用同一个 direct-V4L2 recorder，默认关闭预览和事件解码。它适合 Windows 控制光源、KV260 同步录制的实验。只有一个进程可以拥有 `/dev/video0`。

## 重启后的正确恢复

重启后默认可能只加载 `k26-starter-kits`。先确认：

```sh
sudo xmutil listapps
ls -l /dev/video0 /dev/media0
```

若 IMX636 overlay 未激活，loader 需要包含 `/sbin` 的 PATH，否则内部 `modprobe` 会显示 `command not found`：

```sh
sudo env PATH=/sbin:/usr/sbin:/usr/bin:/bin \
  /usr/bin/load-prophesee-kv260-imx636.sh
```

然后使用仓库恢复入口：

```sh
cd /home/petalinux/Projects/kria-kv260-starter
KV260_SUDO_PASSWORD='<board-password>' \
  ./scripts/kv260-launch-desktop-viewer.sh --recover
```

不要连续反复 unload/load overlay。当前内核会记录 device-tree overlay refcount/memory-leak warnings；优先一次干净重启、一次正确 loader、一次 viewer 启动。

## 正确诊断层级

按以下顺序判断：

1. `xmutil listapps` 确认 `prophesee-kv260-imx636` active slot。
2. `/dev/media0` 和 `/dev/video0` 存在。
3. `v4l2-ctl --list-devices` 显示 Prophesee pipeline。
4. Bias controls 可从 IMX636 subdevice 读取。
5. Native HAL 日志显示 camera opened 和 data-transfer run。
6. 在传感器前制造真实亮度变化，确认 CD events 增加。
7. 最后才验证自定义 recorder、sidecar drops 和 replay。

不能使用以下推理：

```text
static scene -> no new V4L2 payload -> camera broken
```

正确推理是：

```text
static scene -> possibly no new events -> fixed-buffer-count probe may wait
```

## 本次审计状态

- 真正 reboot 已由 boot ID 变化确认。
- IMX636 overlay、media node、video node 和六个 bias controls 均已发现。
- 所有 bias 保持默认值，没有通过提高阈值伪造低事件率。
- Native HAL 使用明确 sensor path 成功打开并产生 CD events。
- 测试模式已恢复为 `Pixel Array`。
- Native viewer、custom GUI 和 API 最终均停止，`/dev/video0` 已释放。
- STM32 固件与灯光控制没有在本次相机审计中修改。

## 与 DualLampHI 的关系

Windows `DualLampHI` 负责 STM32 光源波形、C12880 光谱和事件实验编排。KV260 只负责事件流。优化实验必须分别验证：

```text
light modulation exists
event-camera optical branch sees that modulation
recording contains valid EVT2.1 data
merged illumination reduces events relative to single-source baselines
```

低事件文件只有在相机分支已确认看见调制、且无 writer drops/data loss 时，才能解释为真实光学互补。
