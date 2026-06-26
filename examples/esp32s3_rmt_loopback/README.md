# RMT — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.RMT`** remote-control (pulse TX/RX) driver
(in `libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It
transmits a pulse burst and receives it back over DMA-free symbol RAM **with no
external wiring**.

```
[rmt] bare-metal RMT TX->RX single-pad loopback self-test (no wiring)
[rmt] loopback: sent=4 received=4 durations-match=y  PASS
[rmt]   got[0] = {1:50, 0:60}
[rmt]   got[1] = {1:80, 0:90}
[rmt]   got[2] = {1:120, 0:130}
[rmt]   got[3] = {1:160, 0:0}
```

## What it checks

A TX channel is configured at a 1 µs tick and transmits four distinctive symbols
(`{high 50 µs, low 60 µs}`, `{80, 90}`, `{120, 130}`, `{160, 170}`) on GPIO4. An
RX channel reads that **same pad** back — the GPIO matrix loops the pad's output
into the RX input, so nothing is wired — captures the burst into its symbol RAM,
and the driver returns the decoded `{level, duration}` symbols.

The captured highs (50/80/120/160 µs) and lows (60/90/130 µs) match what was
sent, tick for tick. (The final low comes back as `0`: standard RMT behaviour —
the idle period that ends reception truncates the last symbol's second pulse, so
the test compares every duration except that last low.) This verifies the TX
path, the RX path and the tick divider on silicon.

## Using the driver

```ada
with ESP32S3.RMT; use ESP32S3.RMT;

declare
   Tx : TX_Channel;
   Rx : RX_Channel;
   Got : Symbol_Array (0 .. 15);
   N   : Natural;
begin
   Claim (Tx, 0);  Claim (Rx, 0);
   Configure (Tx, Resolution_Hz => 1_000_000, Pin => 4);
   Configure (Rx, Resolution_Hz => 1_000_000, Pin => 4);
   Start    (Rx);                          -- arm the receiver
   Transmit (Tx, Symbols);                 -- blocking
   Receive  (Rx, Got, N);                  -- blocking until idle
end;                                       -- both channels released
```

Eight channels — `0 .. 3` transmit, `4 .. 7` receive — with distinct
`TX_Channel` / `RX_Channel` handle types. Because they use finalization, the
driver is **embedded/full only** (light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_rmt_loopback           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`.
