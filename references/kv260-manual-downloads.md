# KV260 Prophesee Downloads (Manual / Login Required)

Use this as the “I still need to download” checklist.

## Requires Prophesee customer access

- Linux image for SD card flash
- RPM packets for previous-version upgrade
- SDK/toolchain archive (checksum seen in docs: `7397d862bb6c98d7eb64328b8922f51d`)
- Active Marker source code (`rpi-pico-active-marker.zip`)

Where these are linked from:
- `https://support.prophesee.ai/portal/en/kb/articles/starter-kit-amd-kria-kv260`
- `https://support.prophesee.ai/portal/en/kb/prophesee-1/metavision-evks-rdks/embedded-starter-kits/starter-kit-amd-kria-kv260`

## Public/open references only (already captured locally)

- Official docs and manuals:
  - `https://docs.prophesee.ai/amd-kria-starter-kit/kv260-starter-kit-manual.html`
  - `https://docs.prophesee.ai/amd-kria-starter-kit/application/app_deployment.html`
- AMD kit page and quickstart:
  - `https://www.amd.com/en/products/system-on-modules/kria/k26/kv260-vision-starter-kit/event-based-vision-starter-kit.html`
  - `https://www.prophesee-cn.com/quickstart-prophesee-metavision-starter-amd-kria-kv260/`

## Git source (public)

- `https://github.com/prophesee-ai/petalinux-projects`
- `https://github.com/prophesee-ai/linux-sensor-drivers`
- `https://github.com/prophesee-ai/zynq-video-drivers`
- `https://github.com/prophesee-ai/fpga-projects`
- `https://github.com/LogicTronixInc/Kria-Prophesee-Event-VitisAI`

## Access status (2026-05-27)

- `https://support.prophesee.ai/portal/en/kb/articles/starter-kit-amd-kria-kv260`
  - Route is JS-driven; current extraction shows only partial text and a login flow.
- `https://support.prophesee.ai/portal/en/kb/articles/starter-kit-amd-kria-kv260-release-notes`
  - Release notes currently available.
- API calls to gated endpoints (example):
  - `/portal/api/kbArticles/articleByPermalink` return `FORBIDDEN` when unauthenticated.
- Protected KB article endpoint:
  - `PROPHESSEE_KRIA_MAIN_ARTICLE_API` in `.env` returns `403` without a browser-authenticated session cookie.

Action from a browser session:

- Log in in a normal browser (Windows/desktop) and then use a cookie export (or manually download from the KB page).
- This workspace exposes `.env` keys and a helper script:
  - `PROPHESSEE_SUPPORT_AUTH_WORKFLOW`
  - `PROPHESSEE_SUPPORT_SESSION_COOKIE_FILE`
  - `PROPHESSEE_SUPPORT_HELPER_ARTICLE_DUMP_SCRIPT=$PROJECT_ROOT/scripts/prophesee-support-dump.sh`

Example:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/prophesee-support-dump.sh --cookie-file /path/to/prophesee-cookies.txt
```

To attempt artifact downloads after you have an authenticated cookie jar:

```bash
./scripts/prophesee-support-dump.sh --cookie-file /path/to/prophesee-cookies.txt --download
```
