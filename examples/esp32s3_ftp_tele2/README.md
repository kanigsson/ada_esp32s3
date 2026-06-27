# esp32s3_ftp_tele2 — real-world FTP over the W5500

A real-world `FTP_Client` run against the public **Tele2 speedtest** FTP server
(`speedtest.tele2.net`, anonymous **vsftpd**). It's the FTP analogue of
`esp32s3_tls_weather`, but brings the link up with **DHCP** — the router supplies
the IP, gateway *and* DNS, so there's nothing to hand-configure for your LAN.

It:
1. resolves `speedtest.tele2.net` via public DNS (8.8.8.8),
2. logs in **anonymously**,
3. `SIZE` + `RETR` a small test file (`/1KB.zip`) — counting bytes, since it's a
   binary `.zip`,
4. `STOR` a 256-byte test file to `/upload/` (the server auto-deletes it),
5. `NLST` the root directory, and `QUIT`.

Passive mode, binary — the embedded-friendly profile (only outbound
connections).

## Run

```
./x run esp32s3_ftp_tele2
```

Plug the W5500 into a LAN with a **DHCP server** and internet access — the board
gets its IP, gateway and DNS from the router (no editing needed). Make sure
outbound FTP (port 21, passive data) is permitted on your network — some
networks/firewalls block FTP.

**DHCP or static.** `Bring_Up` takes a `W5500_Dev.IP_Settings`; `main.adb`
defaults to `W5500_Dev.DHCP_Config`. For a fixed address, set it to a static
config instead (the alternative is shown commented at the top of `main.adb`):

```ada
Net_Config : constant W5500_Dev.IP_Settings :=
  (Use_DHCP => False,
   IP      => ESP32S3.W5500.IPv4 (192, 168, 1, 50),
   Subnet  => ESP32S3.W5500.IPv4 (255, 255, 255, 0),
   Gateway => ESP32S3.W5500.IPv4 (192, 168, 1, 1),
   DNS     => ESP32S3.W5500.IPv4 (8, 8, 8, 8));
```

## Expected output (abridged)

```
[ftp] real-world FTP client -> speedtest.tele2.net (anonymous)
[w5500] link up; DHCP IP 192.168.1.50 gw 192.168.1.1 dns 192.168.1.1
[ftp] resolving speedtest.tele2.net via 192.168.1.1 ...
[ftp] speedtest.tele2.net = 90.130.70.73
[ftp] logged in.
[ftp] SIZE /1KB.zip = 1024 bytes
[ftp] RETR /1KB.zip: 1024 bytes received, result OK
[ftp] STOR /upload/esp32s3_ftp_test.bin (256 bytes): OK
[ftp] --- NLST / ---
1KB.zip
1MB.zip
...
[ftp] done.
```

## Verification status

The `FTP_Client` protocol is verified on the host against a real, RFC-compliant
server (see `libs/esp32s3_hal/test/ftp_host` — also runnable against `pyftpdlib`,
which is what `vsftpd`-class servers behave like). This example is the same code
over the W5500 backend and **builds for the target**; the live run against tele2
needs a board on a network that permits outbound FTP (it can't be exercised from
a sandboxed CI, where port 21 is typically blocked). The plain-LAN
`esp32s3_ftp` example pairs with the bundled local test server for a
self-contained run.
