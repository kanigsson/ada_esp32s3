# esp32s3_multinic — multiple network interfaces, routing & pinning

Two W5500s on one board, the routing table that chooses between them, and
interface pinning — the multi-interface stack end to end.

- **Interface 0** — the primary W5500 (CS=IO40 is the *secondary*; the primary is
  the board's usual W5500 on CS=IO39), cabled, brought up by **DHCP**.
- **Interface 1** — a second W5500 on **CS=IO40, INT=IO2**, present on the SPI bus
  but **not plugged into a network**, so its PHY link stays **down**.

The down second interface is the point: the routing table must avoid it, and a
socket pinned to it must fail closed.

## Shared reset (IO11)

Both W5500s share the reset line on **IO11**. The primary is brought up with the
hardware reset (which resets *both* chips once); the secondary is then brought up
with **no reset pin** and a **software reset** (`MR.RST`), which resets only that
chip and leaves the configured primary alone. Both share SPI2 (SCLK=IO1, MOSI=IO4,
MISO=IO45) and each drives its own CS as a GPIO, so the bus is shared cleanly.

## Run

```
./x run esp32s3_multinic
```

Expected serial log (with the second W5500 present but uncabled):

```
[nic] multi-interface routing demo (two W5500s)
[w5500] link up; IP 192.168.1.229 gw 192.168.1.254 dns ...
[nic] secondary W5500 present (CS=IO40), configured 10.0.0.2
[nic] eth0 link up: yes
[nic] eth1 link up: no  (expected no -- not cabled)
[nic] route 8.8.8.8   -> eth0      # both have defaults; eth0 is up + lower metric
[nic] route 10.0.0.5  -> eth0      # eth1's subnet, but eth1 down -> default fallback
[nic] pinned eth1 (down)   -> refused / unreachable   # fail-closed, never re-routed
[nic] routed (-> eth0)     -> CONNECTED                # real connect out the live NIC
[nic] done.
```

## What it shows

- **Liveness** (`Net_Devices.Device.Is_Up`): each interface's PHY link state.
- **Routing** (`Net_Routes`): default routes with metrics (primary preferred), a
  per-subnet route, longest-prefix match, and the live-interface filter — a route
  whose interface is down is skipped, falling back to the next match.
- **Pinning** (`GNAT.Sockets.Set_Interface`): a socket bound to one interface that
  **fails closed** when that interface is down rather than leaking onto another.

Adding a third interface (another W5500, or a cellular modem implementing
`Net_Devices.Device`) is the same shape: bring it up, `Add_Interface`, give it
routes.
