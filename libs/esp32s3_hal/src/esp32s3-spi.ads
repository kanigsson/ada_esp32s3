with System;
with Ada.Finalization;
with ESP32S3.GPIO;

--  ESP32-S3 general-purpose SPI master (SPI2 / SPI3), task-safe.
--
--  This is the ONLY SPI interface the application sees.  The raw register
--  driver lives in the private child ESP32S3.SPI.Engine (un-`with`-able from
--  outside this subtree), so the unsynchronised "ZFP" primitives can't be
--  called by accident -- access is always mediated here.
--
--  Each host is guarded by a protected object; Acquire hands out a limited,
--  non-copyable Session that owns the host exclusively (other tasks suspend on
--  Acquire until it is released).  The blocking DMA Transfer runs OUTSIDE the
--  protected lock -- the lock only arbitrates ownership.  A Session releases
--  automatically when it goes out of scope.
--
--  Requires a tasking runtime (Jorvik light-tasking or richer).
package ESP32S3.SPI is

   --  The two general-purpose hosts (SPI0/SPI1 are the flash/PSRAM controllers
   --  and are deliberately not offered).
   type SPI_Host is (SPI2, SPI3);

   --  SPI clock polarity/phase mode (0 .. 3).
   subtype SPI_Mode is Natural range 0 .. 3;

   --  Sentinel for Configure_Pins: leave that line unrouted (= ESP32S3.GPIO.No_Pin).
   No_Pin : constant ESP32S3.GPIO.Pad_Number := ESP32S3.GPIO.No_Pin;

   --  An exclusive hold on a host.  Limited (cannot be copied -- two tasks can
   --  never share one) and CONTROLLED: it releases the host automatically when
   --  it goes out of scope, including during exception unwinding, so a fault
   --  between Acquire and Release can't leak the lock.  Release stays available
   --  to hand the host back early (it is idempotent).  This relies on
   --  finalization, so these task-safe drivers target the embedded/full profile.
   type Session is limited private;

   ----------------------------------------------------------------------------
   --  One-time host configuration -- call once per host at startup, before any
   --  task contends for it (single-threaded).
   ----------------------------------------------------------------------------

   --  Bring Host up as a full-duplex master at the given mode and bit clock
   --  (Hz, clamped to ~80 kHz .. 80 MHz) and Claim its GDMA channel.
   procedure Setup (Host     : SPI_Host;
                    Mode     : SPI_Mode := 0;
                    Clock_Hz : Positive := 1_000_000);

   --  Change just the bit clock of a Setup host (Hz, same clamp as Setup), with
   --  no GDMA re-Claim.  Lets a driver init a device slowly then run it fast
   --  (e.g. an SD card: <=400 kHz to initialise, then several MHz for data).
   procedure Set_Clock (Host : SPI_Host; Hz : Positive);

   --  Internal MOSI->MISO loopback through one GPIO pad (self-test; no wiring).
   procedure Enable_Loopback (Host : SPI_Host; Pad : ESP32S3.GPIO.Pin_Id);

   --  Route the host's signals to physical pads for an external device.  Each
   --  line is a validated GPIO pin (reserved/absent pads are caught at compile
   --  or run time); pass No_Pin to leave a line unrouted.
   procedure Configure_Pins (Host : SPI_Host;
                             Sclk : ESP32S3.GPIO.Optional_Pin;
                             Mosi : ESP32S3.GPIO.Optional_Pin;
                             Miso : ESP32S3.GPIO.Optional_Pin;
                             Cs   : ESP32S3.GPIO.Optional_Pin := No_Pin);

   ----------------------------------------------------------------------------
   --  Concurrent, mutually-exclusive use.
   ----------------------------------------------------------------------------

   --  Raised by Acquire if Host was never Setup -- configuration must precede
   --  ownership (see the one-time configuration section above).
   Not_Initialized : exception;

   --  Raised by Transfer if its Session does not currently hold a host.  The
   --  transfer reaches the hardware only through one ownership-checked gateway
   --  in the body, so "transfer without holding the host" fails loudly.
   Not_Owned : exception;

   --  Take exclusive ownership of a Setup host.  Suspends until no other task
   --  holds it.  Keep it across a whole transaction, then Release / let it go
   --  out of scope.  Raises Not_Initialized if Host was never Setup.
   procedure Acquire (S : in out Session; Host : SPI_Host);

   --  Full-duplex DMA transfer of Length bytes (1 .. 4095) on the held host:
   --  shift Tx out on MOSI, capture MISO into Rx.  Blocking.  Buffers in
   --  internal SRAM.  Raises Not_Owned unless S currently holds a host.
   procedure Transfer (S : Session; Tx, Rx : System.Address; Length : Natural);

   --  Relinquish ownership (lets a waiting task proceed).  Harmless if already
   --  released.  Always release a Session you Acquired.
   procedure Release (S : in out Session);

private
   type Session is new Ada.Finalization.Limited_Controlled with record
      Host   : SPI_Host := SPI2;
      Active : Boolean  := False;   --  holds Host's guard
   end record;
   overriding procedure Finalize (S : in out Session);   --  auto-release on scope exit
end ESP32S3.SPI;
