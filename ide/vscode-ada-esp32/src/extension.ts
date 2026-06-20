// Ada ESP32-S3 status-bar extension.
//
// Replicates the Espressif ESP-IDF toolbar (build / flash / monitor / "flame" /
// debug + persistent example & port selectors). Two modes, auto-detected from the
// workspace:
//   * REPO mode      -- the workspace is this SDK repo (has ./x): actions take an
//                       example and drive `./x <cmd> <example>`.
//   * STANDALONE mode -- the workspace is a single esp32-ada project (has build.sh
//                       + app.gpr, no ./x): actions drive `esp32-ada <cmd>` on the
//                       project itself (no example selector). The SDK is found via
//                       the `ada-esp32.sdkPath` setting, $ESP32S3_ADA_SDK, or PATH.
import * as vscode from 'vscode';
import { execFile, spawn, ChildProcess } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

const EXAMPLE_KEY = 'ada-esp32.example';
const PORT_KEY = 'ada-esp32.port';
const PROFILE_KEY = 'ada-esp32.profile';
const PROFILES = ['auto', 'light-tasking', 'embedded', 'full'];

interface ExampleInfo { id: string; name: string; dir: string; profile: string; }

let ctx: vscode.ExtensionContext;
let term: vscode.Terminal | undefined;
let openocd: ChildProcess | undefined;   // OpenOCD owned by the Debug button (see startOpenocd)
let exampleItem: vscode.StatusBarItem;
let portItem: vscode.StatusBarItem;
let profileItem: vscode.StatusBarItem;

let mode: 'repo' | 'standalone' = 'repo';
let sdkPath = '';   // the SDK location (== workspace in repo mode; resolved in standalone)

// ---- workspace ----
function root(): string | undefined {
  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}
function cfg<T>(key: string, def: T): T {
  return vscode.workspace.getConfiguration('ada-esp32').get<T>(key, def);
}
function shortName(id: string): string {
  return id.replace(/^esp32s3_/, '') || id;
}

// repo mode: the workspace IS the SDK; standalone: resolve it (setting -> env ->
// derive from `esp32-ada` resolving itself; '' means "rely on PATH").
function detectMode(r: string): 'repo' | 'standalone' {
  if (fs.existsSync(path.join(r, 'x'))) return 'repo';
  if (fs.existsSync(path.join(r, 'build.sh')) && fs.existsSync(path.join(r, 'app.gpr'))) return 'standalone';
  return 'repo';
}
function resolveSdk(r: string): string {
  if (mode === 'repo') return r;
  const s = cfg<string>('sdkPath', '');
  if (s && fs.existsSync(path.join(s, 'tools/bin/esp32-ada'))) return s;
  if (process.env.ESP32S3_ADA_SDK && fs.existsSync(path.join(process.env.ESP32S3_ADA_SDK, 'x'))) {
    return process.env.ESP32S3_ADA_SDK;
  }
  return '';   // unknown -> we'll call bare `esp32-ada` and hope it's on PATH
}
function sdk(): string { return sdkPath || root() || ''; }

// The driver binary to exec, the string to type in a terminal, and the env.
function driverBin(r: string): string {
  if (mode === 'repo') return path.join(r, 'x');
  return sdkPath ? path.join(sdkPath, 'tools/bin/esp32-ada') : 'esp32-ada';
}
function driverDisplay(r: string): string {
  if (mode === 'repo') return './x';
  return sdkPath ? shq(path.join(sdkPath, 'tools/bin/esp32-ada')) : 'esp32-ada';
}
function driverEnv(): NodeJS.ProcessEnv {
  return (mode === 'standalone' && sdkPath) ? { ...process.env, ESP32S3_ADA_SDK: sdkPath } : process.env;
}

// ---- state (Memento, seeded from settings) ----
function getExample(): string | undefined {
  return ctx.workspaceState.get<string>(EXAMPLE_KEY) || cfg('defaultExample', '') || undefined;
}
function getPort(): string {
  return ctx.workspaceState.get<string>(PORT_KEY) || cfg('defaultPort', '/dev/ttyACM0');
}
async function setExample(id: string) { await ctx.workspaceState.update(EXAMPLE_KEY, id); refresh(); }
async function setPort(p: string) { await ctx.workspaceState.update(PORT_KEY, p); refresh(); }
function getProfile(): string {
  return ctx.workspaceState.get<string>(PROFILE_KEY) || cfg('defaultProfile', 'auto');
}
async function setProfile(p: string) { await ctx.workspaceState.update(PROFILE_KEY, p); refresh(); }
// '--profile X' for build/run, or [] when 'auto' (repo: the example's own; standalone: esp32-ada's default)
function profArgs(): string[] { const p = getProfile(); return p && p !== 'auto' ? ['--profile', p] : []; }

// ---- run the driver ----
function shq(s: string): string {
  return /^[\w@%+=:,./-]+$/.test(s) ? s : `'${s.replace(/'/g, `'\\''`)}'`;
}
function getTerminal(r: string): vscode.Terminal {
  if (!term || term.exitStatus !== undefined) {
    term = vscode.window.createTerminal({ name: 'Ada ESP32', cwd: r });
  }
  return term;
}
function runX(r: string, args: string[]) {
  const t = getTerminal(r);
  t.show(true);
  t.sendText(driverDisplay(r) + ' ' + args.map(shq).join(' '));
}
function execX(r: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(driverBin(r), args, { cwd: r, env: driverEnv(), maxBuffer: 1 << 20 }, (err, stdout, stderr) => {
      if (err) reject(new Error(stderr?.toString() || err.message));
      else resolve(stdout.toString());
    });
  });
}

// ---- selectors ----
async function selectExample(r: string): Promise<string | undefined> {
  let list: ExampleInfo[];
  try {
    list = JSON.parse(await execX(r, ['list', '--json']));
  } catch (e: any) {
    vscode.window.showErrorMessage(`Ada ESP32: ./x list failed: ${e.message ?? e}`);
    return;
  }
  const cur = getExample();
  const items = list
    .sort((a, b) => (a.id === cur ? -1 : b.id === cur ? 1 : 0))
    .map(it => ({
      label: (it.id === cur ? '$(check) ' : '') + it.name,
      description: it.profile,
      detail: it.dir,
      id: it.id,
    }));
  const sel = await vscode.window.showQuickPick(items, { placeHolder: 'Select example' });
  if (sel) { await setExample(sel.id); return sel.id; }
  return undefined;
}

async function selectPort(): Promise<string | undefined> {
  let devs: string[] = [];
  try {
    devs = fs.readdirSync('/dev')
      .filter(d => /^(ttyACM|ttyUSB|tty\.usb|cu\.usb)/.test(d))
      .sort();
  } catch { /* /dev unreadable */ }
  const cur = getPort();
  const items: vscode.QuickPickItem[] = devs.map(d => ({
    label: '/dev/' + d,
    description: '/dev/' + d === cur ? '(current)' : '',
  }));
  items.push({ label: '$(edit) Enter custom port…' });
  const sel = await vscode.window.showQuickPick(items, { placeHolder: 'Select serial port' });
  if (!sel) return;
  let port = sel.label;
  if (port.startsWith('$(edit)')) {
    port = (await vscode.window.showInputBox({ prompt: 'Serial port path', value: cur })) || '';
    if (!port) return;
  }
  await setPort(port);
  return port;
}

async function selectProfile(): Promise<string | undefined> {
  const cur = getProfile();
  const sel = await vscode.window.showQuickPick(
    PROFILES.map(p => ({
      label: (p === cur ? '$(check) ' : '') + p,
      description: p === 'auto' ? (mode === 'repo' ? "the example's own profile" : 'esp32-ada default (light-tasking)') : '',
      id: p,
    })),
    { placeHolder: 'Runtime profile for build / run / debug' });
  if (sel) { await setProfile(sel.id); return sel.id; }
  return undefined;
}

// returns the current example, prompting once if unset -- or if the saved one is
// STALE.  A persisted example id can outlive its folder (e.g. the "jorvik_" prefix
// dropped from the example names), so validate it against `./x list` and re-prompt
// rather than feed a non-existent name to `./x build`.  (repo mode only)
async function ensureExample(r: string): Promise<string | undefined> {
  const cur = getExample();
  if (cur) {
    try {
      const list: ExampleInfo[] = JSON.parse(await execX(r, ['list', '--json']));
      if (list.some(it => it.id === cur)) return cur;
      await ctx.workspaceState.update(EXAMPLE_KEY, undefined);
      refresh();
      vscode.window.showWarningMessage(
        `Ada ESP32: saved example "${cur}" no longer exists (renamed/removed) — pick one.`);
    } catch {
      return cur;   // can't reach ./x list (offline) -- trust the stored value
    }
  }
  return await selectExample(r);
}

// In repo mode an action needs an example; in standalone the workspace IS the
// project. Returns the example id (repo) or '' (standalone), or undefined to abort.
async function target(r: string): Promise<string | undefined> {
  if (mode === 'standalone') return '';
  return ensureExample(r);
}
// Build the driver argv: `<cmd> [<example>] <rest...>`.
function argv(id: string, cmd: string, ...rest: string[]): string[] {
  return id ? [cmd, id, ...rest] : [cmd, ...rest];
}

// ---- actions ----
async function doBuild(r: string) { const e = await target(r); if (e !== undefined) runX(r, argv(e, 'build', ...profArgs())); }
async function doFlash(r: string) { const e = await target(r); if (e !== undefined) runX(r, argv(e, 'flash', '-p', getPort())); }
async function doBuildFlash(r: string) {
  const e = await target(r); if (e === undefined) return;
  const d = driverDisplay(r);
  const pf = profArgs().map(shq).join(' ');
  const ex = e ? ' ' + shq(e) : '';
  getTerminal(r).show(true);
  getTerminal(r).sendText(`${d} build${ex}${pf ? ' ' + pf : ''} && ${d} flash${ex} -p ${shq(getPort())}`);
}
async function doRun(r: string) { const e = await target(r); if (e !== undefined) runX(r, argv(e, 'run', '-p', getPort(), ...profArgs())); }
function doMonitor(r: string) { runX(r, ['monitor', '-p', getPort()]); }
async function doClean(r: string) {
  const e = await target(r); if (e === undefined) return;
  const name = e ? shortName(e) : path.basename(r);
  if (cfg('confirmClean', true)) {
    const ok = await vscode.window.showWarningMessage(`Clean ${name} build artifacts?`, { modal: true }, 'Clean');
    if (ok !== 'Clean') return;
  }
  runX(r, argv(e, 'clean'));
}

// Tear down the OpenOCD we started for a debug session.
function killOpenocd() {
  if (openocd) { try { openocd.kill('SIGTERM'); } catch { /* already gone */ } openocd = undefined; }
}

// Start OpenOCD ourselves, pinned (via $ESPPORT, see tools/openocd.sh) to the
// CURRENTLY selected port's board, and resolve once it is listening on :3333.
// (tools/openocd.sh lives in the SDK -- the workspace in repo mode, sdkPath in
// standalone.)  We own the process so it's freshly pinned to getPort() every launch
// -- a reused/stale shared instance would attach GDB to the wrong board, so the temp
// HW breakpoint at app_main never matches and you sail past it.
function startOpenocd(): Promise<void> {
  return new Promise((resolve, reject) => {
    // Single-core (core 0) by default: under Native Debug's async resume, a dual-core
    // attach lets core 1 free-run into a ROM illegal instruction during boot and halt
    // the pair before app_main is reached. Opt into dual-core with `ada-esp32.debugDualCore`.
    const env: NodeJS.ProcessEnv = { ...process.env, ESPPORT: getPort() };
    if (!cfg('debugDualCore', false)) env.ESP_ONLYCPU = '1';
    const oc = spawn(path.join(sdk(), 'tools/openocd.sh'), [], { cwd: sdk(), env });
    openocd = oc;
    let settled = false, buf = '';
    const onData = (d: Buffer) => {
      buf += d.toString();
      if (!settled && /Listening on port 3333/.test(buf)) { settled = true; resolve(); }
    };
    oc.stdout?.on('data', onData);
    oc.stderr?.on('data', onData);
    oc.on('error', e => { if (!settled) { settled = true; openocd = undefined; reject(e); } });
    oc.on('exit', code => {
      openocd = undefined;
      if (!settled) {
        settled = true;
        reject(new Error(`OpenOCD exited before listening (code ${code})\n` +
          buf.split('\n').slice(-8).join('\n')));
      }
    });
    setTimeout(() => {
      if (!settled) { settled = true; reject(new Error('OpenOCD did not come up within 20s\n' +
        buf.split('\n').slice(-8).join('\n'))); }
    }, 20000);
  });
}

// Kill every OpenOCD so the captured USB-JTAG adapter (and its /dev/ttyACM serial
// port) is released. Runs `<driver> kill-openocd` (pkill -x openocd).
async function doKillOpenocd(r: string) {
  killOpenocd();
  try {
    const out = await execX(r, ['kill-openocd']);
    vscode.window.showInformationMessage(`Ada ESP32: ${out.trim() || 'OpenOCD killed'}`);
  } catch (e: any) {
    vscode.window.showErrorMessage(`Ada ESP32: kill-openocd failed: ${e.message ?? e}`);
  }
}

async function doDebug(r: string) {
  const e = await target(r); if (e === undefined) return;       // '' in standalone
  const name = e ? shortName(e) : path.basename(r);
  // Native Debug (webfreak.debug), NOT cppdbg: cppdbg has no Xtensa stack unwinding.
  if (!vscode.extensions.getExtension('webfreak.debug')) {
    const pick = await vscode.window.showErrorMessage(
      'Ada ESP32: the "Native Debug" (webfreak.debug) extension is required for debugging.', 'Install');
    if (pick === 'Install') {
      vscode.commands.executeCommand('workbench.extensions.installExtension', 'webfreak.debug');
    }
    return;
  }
  const gdbAbs = path.join(sdk(), 'tools/gdb/xtensa-esp-elf-gdb/bin/xtensa-esp32s3-elf-gdb');
  if (!fs.existsSync(gdbAbs)) {
    const pick = await vscode.window.showWarningMessage('Debug tools not fetched — run get-debug-tools?', 'Fetch', 'Cancel');
    if (pick === 'Fetch') runX(r, ['get-debug-tools']);
    return;
  }
  // Build AND flash before attaching, so the chip runs exactly the app.elf we debug
  // (a stale/mismatched image puts app_main at a different address -> the breakpoint
  // never hits and GDB stays "running").
  try {
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: `Ada ESP32: building ${name}…` },
      () => execX(r, argv(e, 'build', ...profArgs())));
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: `Ada ESP32: flashing ${name}…` },
      () => execX(r, argv(e, 'flash', '-p', getPort())));
  } catch (err: any) {
    vscode.window.showErrorMessage(`Ada ESP32: build/flash failed before debug: ${err.message ?? err}`);
    return;
  }
  // Our own OpenOCD, pinned to the selected board; kill any prior/stray one first.
  try {
    await execX(r, ['kill-openocd']);
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: `Ada ESP32: OpenOCD on ${getPort()}…` },
      () => startOpenocd());
  } catch (err: any) {
    vscode.window.showErrorMessage(
      `Ada ESP32: OpenOCD failed to start: ${err.message ?? err}\n` +
      `If a previous OpenOCD is stuck, click the $(circle-slash) Kill OpenOCD button and retry.`);
    return;
  }
  // app.elf is examples/<id>/app.elf in repo mode, or the workspace root in standalone.
  const elf = e ? '${workspaceFolder}/examples/' + e + '/app.elf' : '${workspaceFolder}/app.elf';
  const config: vscode.DebugConfiguration = {
    name: `Ada ESP32: debug (${name})`,
    type: 'gdb',
    request: 'attach',
    executable: elf,
    target: 'localhost:3333',
    remote: true,
    cwd: '${workspaceFolder}',
    gdbpath: gdbAbs,
    valuesFormatting: 'parseText',
    // Two-stage stop. Native Debug runs `autorun`, then issues its OWN `continue`
    // (attach semantics), so the autorun stop is NOT the resting point. Stage 1
    // (`thb app_main`+`continue`) re-syncs GDB's run-state after `monitor reset
    // halt`; stage 2 (`thb _ada_main`) is where Native Debug's continue lands -- the
    // Ada `Main` (procedure Main -> `_ada_main`), so the cursor opens on user code.
    autorun: [
      'monitor reset halt',
      'maintenance flush register-cache',
      'thb app_main',
      'continue',
      'thb _ada_main',
    ],
  };
  await vscode.debug.startDebugging(vscode.workspace.workspaceFolders![0], config);
}

function human(bytes: number): string {
  if (bytes % (1024 * 1024) === 0) return `${bytes / 1024 / 1024}MB`;
  if (bytes % 1024 === 0) return `${bytes / 1024}KB`;
  return `${bytes}B`;
}
async function doBoardConfig(r: string) {
  const e = await target(r); if (e === undefined) return;
  const name = e ? shortName(e) : path.basename(r);
  let conf: any;
  try {
    conf = JSON.parse(await execX(r, argv(e, 'config', '--json')));
  } catch (err: any) {
    vscode.window.showErrorMessage(`Ada ESP32: config failed: ${err.message ?? err}`);
    return;
  }
  const pick = await vscode.window.showQuickPick(
    [
      { label: `$(symbol-numeric) Flash size: ${conf.flash_size_str}`, action: 'flash-size' },
      { label: `$(chip) PSRAM size: ${human(conf.psram_size)}`, action: 'psram-size' },
      { label: `$(go-to-file) Open board.ads`, action: 'open' },
    ],
    { placeHolder: `Board configuration — ${name}/board.ads` }
  );
  if (!pick) return;
  if (pick.action === 'open') {
    const doc = e ? path.join(r, 'examples', e, 'board.ads') : path.join(r, 'board.ads');
    vscode.window.showTextDocument(vscode.Uri.file(doc));
    return;
  }
  const sz = await vscode.window.showQuickPick(['2MB', '4MB', '8MB', '16MB'], {
    placeHolder: `New ${pick.action === 'flash-size' ? 'flash' : 'PSRAM'} size`,
  });
  if (sz) runX(r, argv(e, 'config', pick.action, sz));
}

// Scaffold a fresh STANDALONE project (the SDK's `esp32-ada init`) and offer to open
// it. Works whenever the SDK is resolvable (workspace = repo, sdkPath setting, or
// $ESP32S3_ADA_SDK) -- you don't need a project already open.
async function doNewProject() {
  const envSdk = process.env.ESP32S3_ADA_SDK;
  const s = (sdkPath && fs.existsSync(path.join(sdkPath, 'tools/bin/esp32-ada'))) ? sdkPath
          : (envSdk && fs.existsSync(path.join(envSdk, 'tools/bin/esp32-ada'))) ? envSdk : '';
  if (!s) {
    vscode.window.showErrorMessage(
      'Ada ESP32: SDK not found — open the SDK repo, set "ada-esp32.sdkPath", or $ESP32S3_ADA_SDK.');
    return;
  }
  const name = await vscode.window.showInputBox({
    prompt: 'New Ada ESP32 project name',
    validateInput: v => /^[A-Za-z][\w-]*$/.test(v) ? undefined : 'start with a letter, then letters / digits / _ / -',
  });
  if (!name) return;
  const parent = await vscode.window.showOpenDialog({
    canSelectFolders: true, canSelectFiles: false, canSelectMany: false,
    openLabel: `Create "${name}" here`,
  });
  if (!parent || !parent[0]) return;
  const dir = path.join(parent[0].fsPath, name);
  if (fs.existsSync(path.join(dir, 'app.gpr'))) {
    vscode.window.showErrorMessage(`Ada ESP32: ${dir} already has a project.`);
    return;
  }
  try {
    await new Promise<void>((res, rej) => execFile(
      path.join(s, 'tools/bin/esp32-ada'), ['init', dir],
      { env: { ...process.env, ESP32S3_ADA_SDK: s } },
      (e, _o, se) => e ? rej(new Error(se?.toString() || e.message)) : res()));
  } catch (e: any) {
    vscode.window.showErrorMessage(`Ada ESP32: new project failed: ${e.message ?? e}`);
    return;
  }
  const open = await vscode.window.showInformationMessage(
    `Created Ada ESP32 project “${name}”.`, 'Open', 'Open in New Window');
  if (open) {
    vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(dir),
      { forceNewWindow: open === 'Open in New Window' });
  }
}

// ---- status bar ----
function refresh() {
  if (mode === 'standalone') {
    // No example selector -- the workspace IS the project. Show its name.
    exampleItem.text = `$(circuit-board) ${path.basename(root() || '')}`;
    exampleItem.command = undefined;
    exampleItem.tooltip = 'Ada ESP32: standalone project (esp32-ada)';
  } else {
    const e = getExample();
    exampleItem.text = e ? `$(circuit-board) ${shortName(e)}` : '$(circuit-board) (no example)';
    exampleItem.backgroundColor = e ? undefined : new vscode.ThemeColor('statusBarItem.warningBackground');
  }
  portItem.text = `$(plug) ${getPort().replace(/^\/dev\//, '')}`;
  profileItem.text = `$(server-environment) ${getProfile()}`;
}

function mkItem(priority: number, text: string, command: string, tooltip: string): vscode.StatusBarItem {
  const it = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, priority);
  it.text = text; it.command = command; it.tooltip = `Ada ESP32: ${tooltip}`;
  it.show();
  ctx.subscriptions.push(it);
  return it;
}

export function activate(context: vscode.ExtensionContext) {
  ctx = context;
  const r = root();
  if (r) { mode = detectMode(r); sdkPath = resolveSdk(r); }

  // New Project (left-most), then selectors, then actions (descending priority)
  mkItem(101, '$(new-folder)', 'ada-esp32.newProject', 'New project (scaffold a standalone esp32-ada app)');
  exampleItem = mkItem(100, '$(circuit-board)', 'ada-esp32.selectExample', 'example (click to change)');
  portItem = mkItem(99, '$(plug)', 'ada-esp32.selectPort', 'serial port (click to change)');
  profileItem = mkItem(98, '$(server-environment)', 'ada-esp32.selectProfile', 'runtime profile (click to change)');
  mkItem(97, '$(symbol-property)', 'ada-esp32.build', 'Build');
  mkItem(96, '$(zap)', 'ada-esp32.flash', 'Flash');
  mkItem(95, '$(tools)', 'ada-esp32.buildFlash', 'Build + Flash');
  mkItem(94, '$(flame)', 'ada-esp32.run', 'Build, Flash and Monitor');
  mkItem(93, '$(device-desktop)', 'ada-esp32.monitor', 'Monitor');
  mkItem(92, '$(debug-alt)', 'ada-esp32.debug', 'Debug');
  mkItem(91, '$(gear)', 'ada-esp32.boardConfig', 'Board configuration');
  mkItem(90, '$(trash)', 'ada-esp32.clean', 'Clean');
  // No $(skull) codicon exists -- $(circle-slash) is the closest "kill / forbid".
  mkItem(89, '$(circle-slash)', 'ada-esp32.killOpenocd', 'Kill all OpenOCD (release captured serial/JTAG ports)');
  refresh();

  // In standalone mode with an unknown SDK, warn once (the driver may still be on PATH).
  if (mode === 'standalone' && !sdkPath) {
    vscode.window.showWarningMessage(
      'Ada ESP32: standalone project, but the SDK was not found. Set "ada-esp32.sdkPath", ' +
      'or launch VS Code from a shell that sourced the SDK export.sh (so esp32-ada is on PATH).');
  }

  const need = (fn: (r: string) => any) => () => {
    const rr = root();
    if (!rr) { vscode.window.showErrorMessage('Ada ESP32: no workspace folder open.'); return; }
    return fn(rr);
  };
  const reg = (id: string, fn: (r: string) => any) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, need(fn)));

  reg('ada-esp32.selectExample', r2 => { if (mode === 'repo') return selectExample(r2); });
  reg('ada-esp32.selectPort', () => selectPort());
  reg('ada-esp32.selectProfile', () => selectProfile());
  reg('ada-esp32.build', doBuild);
  reg('ada-esp32.flash', doFlash);
  reg('ada-esp32.buildFlash', doBuildFlash);
  reg('ada-esp32.run', doRun);
  reg('ada-esp32.monitor', doMonitor);
  reg('ada-esp32.debug', doDebug);
  reg('ada-esp32.boardConfig', doBoardConfig);
  reg('ada-esp32.clean', doClean);
  reg('ada-esp32.killOpenocd', doKillOpenocd);
  // New Project needs no workspace root (resolves the SDK from setting/env), so it's
  // registered directly rather than through need().
  context.subscriptions.push(vscode.commands.registerCommand('ada-esp32.newProject', doNewProject));

  context.subscriptions.push(
    vscode.window.onDidCloseTerminal(t => { if (t === term) term = undefined; }),
    // Tear down the OpenOCD we started once the debug session it served ends.
    vscode.debug.onDidTerminateDebugSession(s => {
      if (s.type === 'gdb' && /^Ada ESP32: debug/.test(s.name)) killOpenocd();
    })
  );
}

export function deactivate() { killOpenocd(); /* items disposed via subscriptions */ }
