" ada_esp32.vim -- Vim commands for bare-metal Ada ESP32-S3.
"
" Two modes, auto-detected from where you open Vim (mirrors the VS Code extension):
"   * REPO mode  -- inside the SDK repo (an `x` dispatcher above you): actions take
"                   an example and drive `./x <cmd> <example>`.
"   * STANDALONE -- inside a single esp32-ada project (build.sh + app.gpr above you,
"                   no `x`): actions drive `esp32-ada <cmd>` on the project (no
"                   example). The SDK is found via $ESP32S3_ADA_SDK or `esp32-ada` on
"                   PATH (source the SDK export.sh).
"
" :AdaEsp32Debug uses the built-in **termdebug** plugin (Vim's GDB frontend) over the
" s3 GDB + OpenOCD -- it relays GDB's frames, so it handles Xtensa correctly (unlike
" cppdbg). Language features come from the Ada Language Server via the .gpr.
"
" Requires Vim 8.1+ with +terminal (termdebug bundled). For debug: run the SDK's
" `get-debug-tools` once and build first.

if exists('g:loaded_ada_esp32') | finish | endif
let g:loaded_ada_esp32 = 1

let g:ada_esp32_example = get(g:, 'ada_esp32_example', '')
let g:ada_esp32_port    = get(g:, 'ada_esp32_port', empty($ESPPORT) ? '/dev/ttyACM0' : $ESPPORT)
" Runtime profile passed to build/run -- 'auto' uses the example's own default.
let g:ada_esp32_profile = get(g:, 'ada_esp32_profile', 'auto')
let s:profiles = ['auto', 'light-tasking', 'embedded', 'full']
function! s:profflag() abort
  return g:ada_esp32_profile ==# 'auto' ? '' : ' --profile ' . shellescape(g:ada_esp32_profile)
endfunction

" --- find a file upward from the cwd, then the current buffer's dir ---
function! s:findup(name) abort
  let l:f = findfile(a:name, escape(getcwd(), ' ') . ';')
  if empty(l:f) && !empty(expand('%:p'))
    let l:f = findfile(a:name, escape(expand('%:p:h'), ' ') . ';')
  endif
  return empty(l:f) ? '' : fnamemodify(l:f, ':p')
endfunction

" --- the SDK location for standalone mode: env, else derive from `esp32-ada` ---
function! s:sdk_path() abort
  if !empty($ESP32S3_ADA_SDK) && filereadable($ESP32S3_ADA_SDK . '/x')
    return $ESP32S3_ADA_SDK
  endif
  let l:e = exepath('esp32-ada')
  return empty(l:e) ? '' : fnamemodify(l:e, ':p:h:h:h')   " tools/bin/esp32-ada -> SDK
endfunction

" --- detect mode -> {mode, proj, sdk, driver, cwd} ---
function! s:detect() abort
  let l:x = s:findup('x')
  if !empty(l:x)
    let l:r = fnamemodify(l:x, ':h')
    return {'mode': 'repo', 'proj': l:r, 'sdk': l:r, 'driver': './x', 'cwd': l:r}
  endif
  let l:gpr = s:findup('app.gpr')
  if !empty(l:gpr)
    let l:p = fnamemodify(l:gpr, ':h')
    if filereadable(l:p . '/build.sh')
      let l:sdk = s:sdk_path()
      let l:drv = empty(l:sdk) ? 'esp32-ada' : shellescape(l:sdk . '/tools/bin/esp32-ada')
      return {'mode': 'standalone', 'proj': l:p, 'sdk': l:sdk, 'driver': l:drv, 'cwd': l:p}
    endif
  endif
  return {'mode': '', 'proj': getcwd(), 'sdk': '', 'driver': '', 'cwd': getcwd()}
endfunction

" --- example helpers (REPO mode only) ---
function! s:examples(sdk) abort
  let l:out = system(a:sdk . '/x list --json')
  if v:shell_error | return [] | endif
  try | return json_decode(l:out) | catch | return [] | endtry
endfunction
function! s:complete_example(A, L, P) abort
  let l:d = s:detect()
  return l:d.mode ==# 'repo' ? map(s:examples(l:d.sdk), 'v:val.name') : []
endfunction
function! s:resolve(sdk, name) abort
  for l:c in [a:name, 'esp32s3_' . a:name]
    if isdirectory(a:sdk . '/examples/' . l:c) | return l:c | endif
  endfor
  return ''
endfunction
function! s:pick_example(sdk) abort
  let l:items = s:examples(a:sdk)
  if empty(l:items) | echohl ErrorMsg | echo 'Ada ESP32: ./x list failed' | echohl None | return | endif
  let l:menu = ['Select Ada ESP32 example:']
  for l:i in range(len(l:items))
    call add(l:menu, printf('%2d. %-14s (%s)', l:i + 1, l:items[l:i].name, l:items[l:i].profile))
  endfor
  let l:c = inputlist(l:menu)
  if l:c >= 1 && l:c <= len(l:items)
    let g:ada_esp32_example = l:items[l:c - 1].id
    redraw | echo 'Ada ESP32 example: ' . l:items[l:c - 1].name
  endif
endfunction
function! s:need_example(sdk, arg) abort
  if !empty(a:arg)
    let l:id = s:resolve(a:sdk, a:arg)
    if empty(l:id) | echohl ErrorMsg | echo 'Ada ESP32: no such example: ' . a:arg | echohl None | return '' | endif
    let g:ada_esp32_example = l:id
  endif
  if empty(g:ada_esp32_example) | call s:pick_example(a:sdk) | endif
  return g:ada_esp32_example
endfunction

" --- context: detect + (repo) ensure example. returns [d, example] or [{}, ''] ---
function! s:ctx(arg) abort
  let l:d = s:detect()
  if empty(l:d.mode)
    echohl ErrorMsg
    echo 'Ada ESP32: not in an SDK repo (no ./x) or an esp32-ada project (no build.sh + app.gpr)'
    echohl None
    return [{}, '']
  endif
  let l:e = ''
  if l:d.mode ==# 'repo'
    let l:e = s:need_example(l:d.sdk, a:arg)
    if empty(l:e) | return [{}, ''] | endif
  endif
  return [l:d, l:e]
endfunction

" --- build a subcommand: <driver> <sub> [<example>] <rest> ---
function! s:sub(d, e, sub, rest) abort
  return a:d.driver . ' ' . a:sub . (empty(a:e) ? '' : ' ' . shellescape(a:e)) . a:rest
endfunction

" --- run a command in a terminal split, in the project/repo dir ---
function! s:term(d, cmd) abort
  let l:full = 'cd ' . shellescape(a:d.cwd) . ' && ' . a:cmd
  if has('nvim')
    botright 15split | enew | call termopen(['bash', '-lc', l:full]) | startinsert
  else
    call term_start(['bash', '-lc', l:full], {'term_rows': 15})
  endif
endfunction

" --- actions ---
function! s:build(a) abort
  let [l:d, l:e] = s:ctx(a:a) | if empty(l:d) | return | endif
  call s:term(l:d, s:sub(l:d, l:e, 'build', s:profflag()))
endfunction
function! s:flash(a) abort
  let [l:d, l:e] = s:ctx(a:a) | if empty(l:d) | return | endif
  call s:term(l:d, s:sub(l:d, l:e, 'flash', ' -p ' . shellescape(g:ada_esp32_port)))
endfunction
function! s:buildflash(a) abort
  let [l:d, l:e] = s:ctx(a:a) | if empty(l:d) | return | endif
  call s:term(l:d, s:sub(l:d, l:e, 'build', s:profflag()) . ' && '
        \ . s:sub(l:d, l:e, 'flash', ' -p ' . shellescape(g:ada_esp32_port)))
endfunction
function! s:run(a) abort
  let [l:d, l:e] = s:ctx(a:a) | if empty(l:d) | return | endif
  call s:term(l:d, s:sub(l:d, l:e, 'run', ' -p ' . shellescape(g:ada_esp32_port) . s:profflag()))
endfunction
function! s:monitor() abort
  let l:d = s:detect()
  if empty(l:d.mode) | call s:ctx('') | return | endif
  call s:term(l:d, l:d.driver . ' monitor -p ' . shellescape(g:ada_esp32_port))
endfunction
function! s:clean(a) abort
  let [l:d, l:e] = s:ctx(a:a) | if empty(l:d) | return | endif
  call s:term(l:d, s:sub(l:d, l:e, 'clean', ''))
endfunction
function! s:config() abort
  let [l:d, l:e] = s:ctx('') | if empty(l:d) | return | endif
  call s:term(l:d, s:sub(l:d, l:e, 'config', ' show'))
endfunction
function! s:example_cmd(arg) abort
  let l:d = s:detect()
  if l:d.mode !=# 'repo'
    redraw | echo 'Ada ESP32: example selection applies only in the SDK repo (standalone = this project)'
    return
  endif
  call s:need_example(l:d.sdk, a:arg)
endfunction
" --- scaffold a fresh STANDALONE project (esp32-ada init), then open it ---
function! s:new(arg) abort
  let l:sdk = s:sdk_path()
  if empty(l:sdk)
    let l:d = s:detect()                       " also accept the repo as the SDK
    if !empty(l:d.sdk) | let l:sdk = l:d.sdk | endif
  endif
  if empty(l:sdk)
    echohl ErrorMsg | echo 'Ada ESP32: SDK not found -- source the SDK export.sh (sets $ESP32S3_ADA_SDK)' | echohl None | return
  endif
  let l:dir = empty(a:arg) ? input('New project directory: ', getcwd() . '/', 'dir') : a:arg
  if empty(l:dir) | return | endif
  let l:dir = fnamemodify(expand(l:dir), ':p')
  let l:out = system(shellescape(l:sdk . '/tools/bin/esp32-ada') . ' init ' . shellescape(l:dir))
  if v:shell_error
    echohl ErrorMsg | echo 'Ada ESP32: init failed: ' . substitute(l:out, '\n', ' ', 'g') | echohl None | return
  endif
  execute 'cd ' . fnameescape(l:dir)
  execute 'edit ' . fnameescape(l:dir . '/src/main.adb')
  redraw | echo 'Ada ESP32: created project in ' . l:dir . '  (cd''d here; :AdaEsp32Run to build+flash)'
endfunction

function! s:port(arg) abort
  let g:ada_esp32_port = empty(a:arg) ? input('Serial port: ', g:ada_esp32_port) : a:arg
  redraw | echo 'Ada ESP32 port: ' . g:ada_esp32_port
endfunction
function! s:complete_profile(A, L, P) abort
  return filter(copy(s:profiles), 'v:val =~ "^" . a:A')
endfunction
function! s:profile(arg) abort
  if !empty(a:arg)
    if index(s:profiles, a:arg) < 0
      echohl ErrorMsg | echo 'Ada ESP32: invalid profile (auto|light-tasking|embedded|full)' | echohl None | return
    endif
    let g:ada_esp32_profile = a:arg
  else
    let l:menu = map(copy(s:profiles), 'printf("%d. %s", v:key + 1, v:val)')
    let l:c = inputlist(['Runtime profile (auto = the example''s own):'] + l:menu)
    if l:c >= 1 && l:c <= len(s:profiles) | let g:ada_esp32_profile = s:profiles[l:c - 1] | endif
  endif
  redraw | echo 'Ada ESP32 profile: ' . g:ada_esp32_profile
endfunction

" --- on-chip debug via termdebug (OpenOCD background + s3 GDB) ---
function! s:stop_ocd() abort
  if exists('s:ocd_job')
    try
      if has('nvim') | call jobstop(s:ocd_job) | else | call job_stop(s:ocd_job, 'term') | endif
    catch | endtry
    unlet s:ocd_job
  endif
endfunction

function! s:debug(a) abort
  let [l:d, l:e] = s:ctx(a:a) | if empty(l:d) | return | endif
  if empty(l:d.sdk)
    echohl ErrorMsg | echo 'Ada ESP32: SDK not found -- set $ESP32S3_ADA_SDK (source export.sh)' | echohl None | return
  endif
  " app.elf: examples/<id>/app.elf in repo mode, the project root in standalone.
  let l:elf = empty(l:e) ? l:d.proj . '/app.elf' : l:d.sdk . '/examples/' . l:e . '/app.elf'
  if !filereadable(l:elf)
    echohl ErrorMsg | echo 'Ada ESP32: app.elf not found -- build first (:AdaEsp32Build)' | echohl None | return
  endif
  let l:gdb = l:d.sdk . '/tools/gdb/xtensa-esp-elf-gdb/bin/xtensa-esp32s3-elf-gdb'
  if !filereadable(l:gdb)
    echohl ErrorMsg | echo 'Ada ESP32: GDB not found -- run the SDK get-debug-tools' | echohl None | return
  endif
  " 1) OpenOCD in the background, pinned to the selected port + single-core (so the
  "    boot-to-breakpoint is reliable -- dual-core lets core 1 fault before app_main).
  "    Kill any stray instance first so we don't attach through a stale pin.
  let s:ocd_log = tempname()
  let l:ocdcmd = 'cd ' . shellescape(l:d.sdk)
        \ . ' && pkill -x openocd 2>/dev/null; sleep 1;'
        \ . ' ESPPORT=' . shellescape(g:ada_esp32_port) . ' ESP_ONLYCPU=1'
        \ . ' tools/openocd.sh > ' . shellescape(s:ocd_log) . ' 2>&1'
  let s:ocd_job = has('nvim') ? jobstart(['bash', '-c', l:ocdcmd]) : job_start(['bash', '-c', l:ocdcmd])
  let l:up = 0
  for l:i in range(150)
    if filereadable(s:ocd_log) && match(join(readfile(s:ocd_log), "\n"), 'Listening on port 3333') >= 0
      let l:up = 1 | break
    endif
    sleep 100m
  endfor
  if !l:up
    echohl ErrorMsg | echo 'Ada ESP32: OpenOCD did not start (see ' . s:ocd_log . ')' | echohl None
    call s:stop_ocd() | return
  endif
  " 2) GDB startup: connect, reset/halt, arm app_main (throwaway, syncs run-state)
  "    and _ada_main (your `procedure Main`). NO 'continue' -- termdebug's :Continue
  "    drives it so the stop is tracked and the source window updates.
  let l:cmds = tempname()
  call writefile([
        \ 'set pagination off',
        \ 'set remotetimeout 20',
        \ 'target remote localhost:3333',
        \ 'monitor reset halt',
        \ 'maintenance flush register-cache',
        \ 'thb app_main',
        \ 'tbreak _ada_main',
        \ ], l:cmds)
  " 3) termdebug, pointed at our s3 GDB + the startup file.
  let g:termdebug_config = get(g:, 'termdebug_config', {})
  let g:termdebug_config['command'] = [l:gdb, '-x', l:cmds]
  if !exists(':Termdebug') | packadd termdebug | endif
  execute 'Termdebug' fnameescape(l:elf)
  redraw
  echo 'Ada ESP32 debug: :Continue -> app_main, :Continue again -> your Main; :Break/:Step/:Over/:Finish.'
endfunction

augroup AdaEsp32Debug
  autocmd!
  autocmd User TermdebugStopPost call s:stop_ocd()
augroup END

" --- commands (mirror the VS Code extension) ---
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32Build      call s:build(<q-args>)
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32Flash      call s:flash(<q-args>)
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32BuildFlash call s:buildflash(<q-args>)
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32Run        call s:run(<q-args>)
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32Clean      call s:clean(<q-args>)
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32Debug      call s:debug(<q-args>)
command! -nargs=? -complete=customlist,s:complete_example AdaEsp32Example    call s:example_cmd(<q-args>)
command! -nargs=? -complete=dir AdaEsp32New call s:new(<q-args>)
command! -nargs=0 AdaEsp32Monitor call s:monitor()
command! -nargs=0 AdaEsp32Config  call s:config()
command! -nargs=? AdaEsp32Port    call s:port(<q-args>)
command! -nargs=? -complete=customlist,s:complete_profile AdaEsp32Profile call s:profile(<q-args>)
