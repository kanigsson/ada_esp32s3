# I2C master — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Hardware self-test for the reusable **`ESP32S3.I2C`** master driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It drives
the I2C0 controller through the task-safe HAL and proves the master works on
silicon **with no external wiring and no device on the bus**.

```
[i2c] bare-metal I2C master hardware self-test (no wiring, no device)
[i2c] test0: PASS
[i2c] test1: PASS
[i2c] test2: PASS
[i2c] done.
```

## What it checks

The master's SDA and SCL are each looped back to their own input on two free
pads (GPIO4 = SDA, GPIO6 = SCL), so the controller drives a real open-drain
bus with the internal pull-ups — there just isn't a device on it.

| test | what the master does | PASS means |
|---|---|---|
| `test0` | ACK-checked write to an **absent** address (`0x55`) | real START + 7-bit address clocked, ACK sampled, **NACK detected**, STOP |
| `test1` | 5-byte write to the same address, **ACK-checking off** | address + data + STOP clocked to **completion** |
| `test2` | acquire the host, **raise an exception** in scope, then re-acquire | the controlled `Session` auto-released on unwind, so the re-acquire succeeds (a leaked lock would deadlock) |

`test0`/`test1` exercise START/STOP generation, 7-bit addressing, the
command-sequence FSM, multi-byte FIFO transmit, the bus timing (XTAL-sourced
divider), and ACK/NACK detection. `test2` verifies the RAII auto-release: the
`Session` is `Limited_Controlled`, so `Finalize` hands the host back even when an
exception unwinds past the explicit `Release` — exercising the embedded profile's
finalization + exception propagation.

## Why there is no internal master↔slave loopback

I2C SDA is a **bidirectional open-drain (wired-AND)** line: every participant
must both *drive* and *read* the same node. The ESP32-S3 GPIO matrix routes
exactly **one output source per pad**, so it cannot wire-AND two on-chip I2C
controllers onto one pad — there is no way to internally connect two
controllers into a working bus:

- **Cross-coupling** (master and slave on two pads, each reading the other's)
  breaks the master: a master must read back its *own* SDA while writing — the
  very START needs SDA-low confirmed — so reading the slave's idle-high pad
  stalls it immediately.
- **A single shared pad** driven only by the master breaks the slave: the slave
  can't drive its ACK (9th bit) back onto a master-owned pad, which corrupts its
  own receive framing.

So the **READ** direction and the ACK handshake can only be verified against a
**real shared bus node**. Two options:

1. **External jumper** — wire two pads together (one for SDA, one for SCL) and
   run a master on one controller + a slave on the other.
2. **A real I2C device** — point `ESP32S3.I2C.Read` / `.Write` at its address.

## Build & flash

```sh
./x run esp32s3_i2c_loopback           # build + flash + monitor
# or:
./x build esp32s3_i2c_loopback
./x flash esp32s3_i2c_loopback -p /dev/ttyACM0
```

The Ada is built against the pinned `esp32s3_rts` runtime by the shared
`examples/common/bare/build_ada.sh`; the report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`.
