# GitHub Repository Metadata

Use this file when creating or polishing the GitHub repository page.

## Repository Name

```text
kria-metavision-lab
```

Suggested full repository:

```text
lachlanchen/kria-metavision-lab
```

## Homepage URL

```text
https://flow.lazying.art
```

## About

Short version:

```text
GUI-first AMD Kria KV260 + Prophesee Metavision lab for event-camera bring-up, custom recording/viewing, PetaLinux tooling, and embedded vision experiments.
```

Longer version:

```text
A practical AMD Kria KV260 and Prophesee Metavision workspace with a custom local event-camera GUI, clean desktop launchers, recording support, V4L2 diagnostics, PetaLinux notes, FPGA and driver references, and embedded event-vision research logs.
```

## Topics

Recommended GitHub topics:

```text
amd-kria
kria
kv260
petalinux
zynqmp
fpga
prophesee
metavision
event-camera
event-based-vision
neuromorphic-vision
imx636
genx320
v4l2
media-controller
x11
embedded-linux
computer-vision
python
gtk
```

## Suggested `gh` Commands

Create the repository:

```sh
gh repo create lachlanchen/kria-metavision-lab --private --source=. --remote=origin
```

Apply the homepage, description, and topics after the repository exists:

```sh
gh repo edit lachlanchen/kria-metavision-lab \
  --homepage "https://flow.lazying.art" \
  --description "GUI-first AMD Kria KV260 + Prophesee Metavision lab for event-camera bring-up, custom recording/viewing, PetaLinux tooling, and embedded vision experiments." \
  --add-topic amd-kria \
  --add-topic kria \
  --add-topic kv260 \
  --add-topic petalinux \
  --add-topic zynqmp \
  --add-topic fpga \
  --add-topic prophesee \
  --add-topic metavision \
  --add-topic event-camera \
  --add-topic event-based-vision \
  --add-topic neuromorphic-vision \
  --add-topic imx636 \
  --add-topic genx320 \
  --add-topic v4l2 \
  --add-topic media-controller \
  --add-topic x11 \
  --add-topic embedded-linux \
  --add-topic computer-vision \
  --add-topic python \
  --add-topic gtk
```

## Public Safety Checklist

Before pushing to a public repository:

```sh
git status --short
git grep -nE 'pass(word|wd)|token|secret|Administrator|192[.]168[.]|[m]dmd|lachen[@]'
```

Recommended rule:

```text
Keep board-local credentials, Windows access notes, authenticated Prophesee downloads, private network details, and local `.env` values out of the public README and public commit history.
```
