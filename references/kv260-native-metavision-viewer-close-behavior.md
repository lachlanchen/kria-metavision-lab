# KV260 Native Metavision Viewer Close Behavior

Generated: 2026-05-31

## Problem Observed

On the KV260 HDMI desktop, the native Prophesee viewer (`/usr/bin/metavision_viewer`) can open and display live events correctly, but closing it with the window manager close button is unreliable.

Observed behavior:

- first close click does not always terminate the process;
- the event preview area can jump to the upper-left corner instead of filling the viewer window;
- a gray/default UI can appear during shutdown;
- if the second or third close click is slow, live event rendering can resume and the window appears again;
- if the second or third close click is fast enough, it can close before event rendering resumes.

This is not considered a normal user-interface design. It is best understood as a partial shutdown/race behavior in the native viewer on this embedded X11/Matchbox stack.

## Confirmed Board Context

The viewer is started on the local X11 desktop:

```text
DISPLAY=:0
X server: xserver-nodm + Xorg + Matchbox
viewer: /usr/bin/metavision_viewer
camera: Prophesee V4L2/HAL pipeline
```

Current successful viewer startup markers from local logs:

```text
[HAL][INFO] V4l2 Discovery with great success +1
Plugin used to open the device: hal_plugin_prophesee
Camera has been opened successfully.
[HAL][INFO] V4l2DataTransfer - start_impl()
[HAL][INFO] V4l2DataTransfer - run_impl()
```

The launcher/toggle log shows process-level close is reliable:

```text
Metavision viewer not running; opening it.
Started viewer (...). Mode: live only (no recording).
Metavision viewer running; closing it.
Stopped metavision viewer.
```

## Why The Close Button Behaves This Way

The most likely cause is a race between several pieces that do not stop at exactly the same instant:

- the X11 window manager sends a close request;
- the viewer UI marks the window as closing;
- the event rendering loop is still receiving frames/events for a short time;
- the V4L2/HAL data-transfer thread is still active until the viewer process fully exits;
- the embedded Matchbox desktop does not provide a richer session manager around the application.

That explains the visible sequence:

```text
normal live view
close requested
canvas/layout partially tears down
preview appears in the upper-left corner
gray/default UI appears
stream/render loop can draw again
window appears alive again unless the process exits or is killed
```

The fast-click behavior is also consistent with this: a second close request can land during the short interval where the UI is closing but before event rendering resumes.

## What Official SDK Docs Support

The official SDK documentation does not describe this exact KV260/Matchbox close bug. The following points support the diagnosis:

- Metavision event display is a generated-frame display pipeline; event streams are transformed into frames before display.
- The UI classes have event queues and close flags; setting the close flag asks a window to close but does not itself destroy the window.
- `MTWindow` uses an internal rendering thread, while `Window` display/event handling must be kept in sync by the application.
- SDK Stream is built on HAL and hides lower-level event-stream and decoder threading issues in most normal cases, but those lower-level producer/consumer and threading concerns still exist below the app.
- Metavision Viewer is one of the SDK Stream sample/tools, so it is a basic viewer path rather than a custom lifecycle controller for this embedded desktop.

## Practical Conclusion

The native viewer is good for quick visual confirmation, but on this board it should not be treated as the most reliable close/record workflow.

Recommended workflow:

```text
Use KV260 Event Camera for normal live view, recording, filename/folder control, and clean close.
Use Metavision Viewer as a native SDK smoke-test/debug viewer.
Close Metavision Viewer through the toggle launcher or helper script instead of the window close button.
```

## Reliable Close Paths

Preferred desktop close path:

```text
Click the Metavision Viewer launcher again.
```

The launcher is a toggle:

```text
first click: open native viewer
second click: stop native viewer process
```

Shell close path:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-visual-gui-local.sh --stop --force
```

The toggle script uses a stronger close sequence:

```text
helper stop
wait for process exit
SIGTERM fallback
SIGKILL fallback if still alive
```

That is why process-level close behaves better than the viewer window close button.

## Why The Custom GUI Is Better For Daily Use

The custom `KV260 Event Camera` GUI does not embed the native `metavision_viewer` window. It owns its own application lifecycle:

- opens `/dev/video0` directly;
- stops streaming before closing the GUI;
- records the raw V4L2 PSE2 stream with a JSON sidecar;
- exposes an explicit `Quit` path;
- accepts a local `quit` socket command from the launcher wrapper.

This makes close behavior deterministic compared with relying on the native viewer's X11 window close handling.

## What Would Be Needed To Truly Fix The Native Viewer

A real native-viewer fix would require one of these:

- source-level changes to `metavision_viewer` shutdown handling;
- a Prophesee SDK-side fix for the relevant viewer/UI lifecycle behavior;
- a different window/session environment than Matchbox on this PetaLinux image;
- an external wrapper that sends a controlled process stop instead of relying on the X11 close button.

In this repository, the last option is already implemented through:

```text
scripts/kv260-metavision-viewer-toggle.sh
scripts/kv260-event-visual-gui-local.sh
```

## Sources

- Prophesee Metavision SDK docs, Streaming and Decoding: https://docs.prophesee.ai/stable/data/streaming_decoding/index.html
- Prophesee Metavision SDK docs, Displaying Frames: https://docs.prophesee.ai/stable/guides/frames_displaying.html
- Prophesee Metavision SDK docs, SDK UI Python bindings: https://docs.prophesee.ai/stable/api/python/ui/bindings.html
- Prophesee Metavision SDK docs, SDK Stream Architecture: https://docs.prophesee.ai/stable/architecture/sdk_stream_architecture.html
- Prophesee Metavision SDK docs, SDK Stream Samples / Metavision Viewer: https://docs.prophesee.ai/stable/samples/modules/stream/index.html
