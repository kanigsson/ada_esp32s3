# esp32s3_ftp — FTP client over the W5500

An **FTP client** over the WIZnet W5500, driven through the portable
`FTP_Client` package (itself written against the `GNAT.Sockets` facade, so the
same code runs on desktop GNAT.Sockets and on the bare-metal W5500 alike).

It logs in, prints a file's `SIZE`, downloads it (`RETR`), lists the directory
(`NLST`), then **tests sending**: it uploads a generated 512-byte file (`STOR`),
reads it back (`RETR`) and verifies it byte-exact — a full upload round-trip from
the board. **Passive mode, binary** (only outbound connections, so it needs no
listening socket and works behind NAT). This is the example to use for a
**board send test**, since it writes to a local server you control (unlike
`esp32s3_ftp_inet`, which targets an anonymous read-only public server).

## Run

```
./x run esp32s3_ftp
```

The board takes the static IP **192.168.1.50** (/24, gateway .254 — set in
`w5500_dev.adb`). Run the bundled upload-capable server on a host on that subnet,
and point `Server_IP` / `Server_Port` (top of `main.adb`) at it:

```
python3 libs/esp32s3_hal/test/ftp_host/ftp_server.py 2121     # serves on :2121, all interfaces
```

It binds all interfaces, accepts any user/password, and accepts uploads — so the
board's `STOR` round-trip works against it. (Any FTP daemon that allows the
configured login to write would also do.)

## Expected output

```
[ftp] W5500 FTP client (FTP_Client over GNAT.Sockets)
[w5500] link up, IP 192.168.1.50
[ftp] connecting to 192.168.1.100:2121 ...
[ftp] logged in.
[ftp] SIZE /hello.txt = 30
[ftp] --- RETR /hello.txt ---
hello from the ftp host test
[ftp] --- NLST ---
hello.txt
[ftp] --- STOR + read-back round-trip ---
[ftp] STOR /from_board.bin (512 bytes): OK
[ftp] read-back 512 bytes: round-trip VERIFIED
[ftp] done.
```

## Where the protocol is verified

The `FTP_Client` protocol logic (login, `SIZE`, `RETR`, `STOR`, round-trip,
`NLST`, `DELE`, `QUIT`) is exercised end-to-end on the host against a real FTP
server by `libs/esp32s3_hal/test/ftp_host/run.sh` — the same source, compiled
against native GNAT.Sockets. This on-board example is the same code over the
W5500 socket backend.

## The data-sink callback

`FTP_Client.Retrieve` / `List` stream their bytes to a `Data_Sink` callback,
which (like every callback in this HAL) must be **library-level and
closure-free** — here `FTP_Print.Put_Chunk`, not a subprogram nested in `Main`.
