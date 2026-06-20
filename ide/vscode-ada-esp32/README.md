# Ada ESP32-S3 — VS Code status-bar extension

Replicates the Espressif ESP-IDF toolbar — clickable **status-bar icons** for build,
flash, monitor, debug, plus persistent **port** and **profile** selectors — no ESP-IDF.
It works in **two modes**, auto-detected from the workspace:

- **Repo mode** — the workspace is this SDK repo (has `./x`): an **example** selector
  appears and actions drive `./x <cmd> <example>`.
- **Standalone mode** — the workspace is a single project created by `esp32-ada init`
  (has `build.sh` + `app.gpr`, no `./x`): there's no example selector (the workspace
  *is* the project) and actions drive **`esp32-ada <cmd>`** on it. The extension finds
  the SDK via the **`ada-esp32.sdkPath`** setting (baked into the scaffolded
  `.vscode/settings.json` by `esp32-ada init`), else `$ESP32S3_ADA_SDK`, else
  `esp32-ada` on `PATH`.

## Status bar (left → right)

| Icon | Action |
|---|---|
| `$(new-folder)` | **New project** — scaffold a fresh standalone `esp32-ada` app (prompts name + folder), then offer to open it. Also in the Command Palette (`Ada ESP32: New Project`), available even with no folder open |
| `$(circuit-board) <example>` | **Select example** (from `./x list --json`) — persists |
| `$(plug) <port>` | **Select serial port** (`/dev/ttyACM*`) — persists |
| `$(server-environment) <profile>` | **Select runtime profile** — `auto` (the example's own), `light-tasking`, `embedded`, `full` — passed to build/run/debug as `--profile`; persists |
| `$(symbol-property)` | Build (`./x build`) |
| `$(zap)` | Flash (`./x flash`) |
| `$(tools)` | Build + Flash |
| `$(flame)` | Build, Flash and Monitor (`./x run`) |
| `$(device-desktop)` | Monitor (`./x monitor`) |
| `$(debug-alt)` | Debug (OpenOCD + GDB) |
| `$(gear)` | Board configuration (`config/board.ads`) |
| `$(trash)` | Clean (`./x clean`) |
| `$(circle-slash)` | Kill all OpenOCD — releases any captured USB-JTAG / serial port (`./x kill-openocd`, i.e. `pkill -x openocd`) |

The selected example/port/profile are remembered per workspace, so a click acts without
re-prompting. All commands are also under **`Ada ESP32:`** in the Command Palette.

In standalone mode the example selector slot shows the project name instead, and
the icons act on the project directly. `config/board.ads` references above are at the
project/example **root** (`board.ads`).

## Requirements
- **Repo mode:** the SDK repo open as the workspace folder. **Standalone mode:** a
  folder with `board.ads` + `build.sh` + `app.gpr` (what `esp32-ada init` creates) —
  with `ada-esp32.sdkPath` set (automatic for scaffolded projects), or VS Code
  launched from a shell that sourced the SDK `export.sh`.
- **Ada & SPARK** (`adacore.ada`) for language features; **C/C++** (`ms-vscode.cpptools`)
  for the `$(debug-alt)` debug action.
- Debug needs the fetched tools — run `./x get-debug-tools` once (the Debug button
  offers to do this if they're missing).

## Install (users — no Node needed)

A prebuilt `vscode-ada-esp32.vsix` is committed to the repo, so installing is one
command (needs only the VS Code `code` CLI on PATH):

```sh
./x install-ide            # or, from a standalone project:  esp32-ada install-ide
```
Then reload VS Code (**Developer: Reload Window**). To **update** after a `git pull`,
run it again — a repo-hosted `.vsix` doesn't auto-update (only Marketplace installs do).

## Build / install (developers)
Needs Node.js + npm (users of the committed `.vsix` do **not**).

```sh
./x build-ide              # = npm install && npm run package -> vscode-ada-esp32.vsix
# then commit the rebuilt vsix (it's tracked) and bump "version" in package.json
```
Or by hand: `cd ide/vscode-ada-esp32 && npm install && npm run package`. Develop with
**F5** (Extension Development Host) + `npm run watch`.
