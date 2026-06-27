# ftp_host — native host test for FTP_Client

Exercises the `FTP_Client` protocol logic end to end against a real FTP server,
on the build host — no board, no network hardware. Because `FTP_Client` is
written entirely against the `GNAT.Sockets` subset, the **same source** compiles
against the native runtime's real GNAT.Sockets here (the bare-metal W5500 facade
is left out of the build whitelist).

## Run

```
./run.sh
```

It builds the harness with a native GNAT (auto-discovered from the Alire
toolchains), starts the bundled stdlib Python FTP server (`ftp_server.py`, no
external deps) on a random port, runs the harness against it, and stops the
server. Exit status is non-zero if any check fails.

## What it checks

| Step | FTP commands |
|---|---|
| `Connect / login` | greeting, `USER`/`PASS`, `TYPE I` |
| `SIZE` | `SIZE` of a seeded file |
| `RETR` content | `PASV` + `RETR`, byte-exact |
| `STOR` | `PASV` + `STOR` (upload) |
| `RETR` round-trip | download what was uploaded, byte-exact |
| `NLST` | passive directory listing |
| `DELE` | delete the uploaded file |
| `Quit` | `QUIT` + close |

## Real-world smoke test

`./run_real.sh [host] [path]` drives the **same** `FTP_Client` source against an
actual public FTP server over the internet (default `ftp.gnu.org /README`):
anonymous login, `SIZE`, `RETR` (byte-counted), `NLST`. This needs network access
(not CI). Confirmed working against `ftp.gnu.org` — `SIZE`/`RETR` byte-exact
(2814 B), real-server PASV and multi-line replies. It's the strongest validation
short of the board itself; only the W5500 socket backend (two simultaneous TCP
sockets) is then untested.

## Files

- `ftp_host.adb` — the offline test driver (checks + exit status).
- `ftp_real.adb` — the real-server smoke-test driver (args: ip port path …).
- `ftp_test_support.{ads,adb}` — the library-level (closure-free) sink/source
  callbacks the API requires; they can't be nested in the driver.
- `ftp_server.py` — minimal passive-mode FTP server (stdlib only).
- `ftp_host.gpr` — whitelist build (only `ftp_client` + the harness).
