# TWAI (CAN) — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.TWAI`** CAN 2.0 driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It sends and
receives **standard (11-bit)** and **extended (29-bit)** data frames and a
**remote-transmission request (RTR)** frame, **with no external transceiver or
wiring**.

```
[twai] bare-metal TWAI (CAN) self-test loopback (no wiring)
[twai] standard(11-bit) data       self-rx: got=1 id=0x123 len=5 match=y  PASS
[twai] extended(29-bit) data       self-rx: got=1 id=0x14abcde len=3 match=y  PASS
[twai] standard(11-bit) remote(RTR) self-rx: got=1 id=0x7a5 len=8 match=y  PASS
[twai] extended(29-bit) remote(RTR) self-rx: got=1 id=0x1f12345 len=6 match=y  PASS
```

## What it checks

The controller is brought up in **self-test mode**, where CAN's normal
requirement for a second node to acknowledge a frame is waived — the controller
can transmit and receive its own message. TX is looped back to RX through one
GPIO pad (the matrix loops the shared TX/RX matrix signal out→in, so nothing is
wired). The test round-trips all four combinations of width × type — a
**standard** and an **extended** data frame, and a **standard** and an
**extended RTR** frame (remote requests carry an id and a requested length but no
payload) — each time comparing the received identifier, width, RTR flag, length
and payload to what was sent.

This exercises the real CAN bit engine — framing, stuffing, CRC, the bit
timing — on silicon, not just a register echo, and across both addressing widths.

## Using the driver

```ada
with ESP32S3.TWAI; use ESP32S3.TWAI;

Setup (Mode => Normal, Bit_Rate => 500_000);      -- once
--  or, for this wiring-free self-test:  Setup (Self_Test);

declare
   S  : Session;
   RE : Extended_Frame;
   Got : Boolean := False;
begin
   Acquire (S);                                   -- own it, then route/loopback
   Configure_Pins (S, Tx => 5, Rx => 6);          -- to an external transceiver
   --  or:  Enable_Loopback (S, Pad => 4);

   --  Send is overloaded on the frame's width (11- vs 29-bit id):
   Send (S, Standard_Frame'(Id => 16#123#, Remote => False, Length => 2,
                            Data => (16#DE#, 16#AD#, others => 0)));
   Send (S, Extended_Frame'(Id => 16#14AB_CDE#, Remote => False, Length => 3,
                            Data => (16#01#, 16#02#, 16#03#, others => 0)));
   --  Remote => True makes it an RTR request (id + length, no data):
   Send (S, Standard_Frame'(Id => 16#7A5#, Remote => True,
                            Length => 8, Data => (others => 0)));

   --  The sender picks the width, so peek before receiving:
   if Available (S) then
      if Is_Extended (S) then Receive (S, RE, Got);  -- handle extended
      else                    null;                  -- ... or a Standard_Frame
      end if;
   end if;
end;                                              -- controller released
```

Standard (11-bit) and extended (29-bit) data frames are distinct types, so the id
is range-checked to its width and `Send`/`Receive` are overloaded on it. The
`Session` is the same limited, controlled handle as SPI. Because it uses
finalization, the driver is **embedded/full only** (light-tasking forbids
`No_Finalization`). For a real bus, wire `Configure_Pins` to a CAN transceiver
(e.g. SN65HVD230).

## Build & flash

```sh
./x run esp32s3_twai_loopback           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
