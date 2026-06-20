--  Ada UART self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  =====================================================================
--  Exercises the reusable HAL UART driver (ESP32S3.UART) with NO external
--  wiring: the controller's own internal TX->RX loopback (CONF0.LOOPBACK) feeds
--  every transmitted byte straight back to the receiver.  UART is push-pull and
--  unidirectional, so -- unlike I2C -- a fully on-chip loopback works and proves
--  the real data path: baud divider, frame format, TX FIFO, RX FIFO.
--
--    test 1  write a known buffer at 115200 8-N-1 -> read it back -> compare.
--    test 2  hardware RTS/CTS flow control: RTS is matrix-looped to CTS on one
--            pad, a low RX threshold is set, then more bytes than the threshold
--            are written without reading.  The RX FIFO should throttle (RTS
--            deasserts -> CTS deasserts -> the CTS-gated transmitter stalls)
--            well below the total, then drain back fully and intact once read.
--
--  A "PASS" line on the USB-Serial-JTAG console confirms each on silicon.  The
--  report goes through the ROM printf glue (the reliable console path here).
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.UART;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the test runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use ESP32S3.UART;

   procedure Banner;
   pragma Import (C, Banner, "native_uart_banner");
   procedure Line (Kind : int);
   pragma Import (C, Line, "native_uart_line");
   procedure Hex (V : int);
   pragma Import (C, Hex, "native_uart_hex");
   procedure Eol;
   pragma Import (C, Eol, "native_uart_eol");
   procedure Verdict (Ok : int);
   pragma Import (C, Verdict, "native_uart_verdict");
   procedure Flow (Capped, Total, Ok : int);
   pragma Import (C, Flow, "native_uart_flow");
   procedure Invert (Tx_Only_Inverted, Tx_Rx_Matched, Ok : int);
   pragma Import (C, Invert, "native_uart_invert");
   procedure Done;
   pragma Import (C, Done, "native_uart_done");

   Port : constant UART_Port := UART1;

   --  A free GPIO that RTS drives and CTS reads back (matrix loopback of the
   --  flow lines; data stays on the controller's internal TX->RX loopback).
   Flow_Pad : constant := 5;
   Threshold : constant := 8;       --  RTS deasserts when RX FIFO hits 8 bytes

   --  A free pad for the inversion test's TXD<->RXD single-pad loopback (CONF0
   --  line-invert applies at the I/O boundary, so this routes through a pad
   --  rather than the controller's internal loopback).
   Inv_Pad : constant := 4;
   Inv_Tx  : constant Byte_Array :=
     (16#00#, 16#FF#, 16#A5#, 16#5A#, 16#0F#, 16#F0#, 16#12#, 16#ED#);

   Tx : constant Byte_Array :=
     (16#55#, 16#AA#, 16#00#, 16#FF#, 16#12#, 16#34#, 16#56#, 16#78#,
      16#9A#, 16#BC#, 16#DE#, 16#F0#, 16#0F#, 16#A5#, 16#5A#, 16#C3#);

   procedure Dump (Kind : int; Data : Byte_Array; Count : Natural) is
   begin
      Line (Kind);
      for I in Data'First .. Data'First + Count - 1 loop
         Hex (int (Data (I)));
      end loop;
      Eol;
   end Dump;

   --  Flow-control test payload: 64 bytes (>> Threshold, < 128-byte FIFO).
   Flow_Tx : Byte_Array (0 .. 63);

   S      : Session;
   Rx     : Byte_Array (Tx'Range);
   Flow_Rx : Byte_Array (Flow_Tx'Range);
   Inv_Rx  : Byte_Array (Inv_Tx'Range);
   Got    : Natural;
   Got2   : Natural;
   Capped : Natural;
   Equal  : Boolean;
   Tx_Only_Broke : Boolean;
   Tx_Rx_Match   : Boolean;
begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Banner;

   Setup (Port, Baud => 115_200);            --  8-N-1 defaults

   Acquire (S, Port);
   Enable_Loopback (S);                      --  internal TX->RX (held port)
   Write (S, Tx);
   Read (S, Rx, Got);
   Release (S);

   Equal := Got = Tx'Length;
   if Equal then
      for I in Tx'Range loop
         if Rx (I) /= Tx (I) then
            Equal := False;
         end if;
      end loop;
   end if;

   Dump (0, Tx, Tx'Length);                  --  sent
   Dump (1, Rx, Got);                        --  recv
   Verdict (Boolean'Pos (Equal));

   ----------------------------------------------------------------------------
   --  Test 2: RTS/CTS hardware flow control.  RTS is matrix-looped to CTS on
   --  Flow_Pad; data still uses the internal TX->RX loopback.  Writing 64 bytes
   --  without reading fills the RX FIFO to ~Threshold, at which point RTS
   --  deasserts -> CTS deasserts -> the CTS-gated transmitter stalls, capping RX
   --  far below 64.  Draining then re-asserts RTS/CTS and the rest flows in.
   ----------------------------------------------------------------------------
   for I in Flow_Tx'Range loop
      Flow_Tx (I) := Byte (I);
   end loop;

   Acquire (S, Port);
   Configure_Pins (S,
                   Rts => Flow_Pad, Cts => Flow_Pad,
                   Rx_Flow_Threshold => Threshold);
   Write (S, Flow_Tx);                       --  64 bytes queued to the TX FIFO
   delay until Clock + Milliseconds (20);    --  let TX run until throttled
   Capped := Available (S);                  --  RX should be stuck near Threshold
   Read (S, Flow_Rx, Got);                   --  drain -> RTS re-asserts -> rest flows
   Release (S);

   Equal := Got = Flow_Tx'Length and then Capped < Flow_Tx'Length;
   if Equal then
      for I in Flow_Tx'Range loop
         if Flow_Rx (I) /= Flow_Tx (I) then
            Equal := False;
         end if;
      end loop;
   end if;
   Flow (int (Capped), Flow_Tx'Length, Boolean'Pos (Equal));

   ----------------------------------------------------------------------------
   --  Test 3: per-line inversion, changed AFTER configure via Set_Inversion.
   --  Data loops TXD->RXD on one pad (CONF0 line-invert applies at the I/O
   --  boundary).  Inverting only TX flips the idle/start-bit polarity the
   --  (non-inverted) RX expects, so the link BREAKS (garbled / short read);
   --  inverting RX as well makes both ends agree again and the bytes match.
   --  That asymmetry proves the inversion takes effect and is per-line.
   ----------------------------------------------------------------------------
   --  TX inverted only -> polarity mismatch -> link should NOT round-trip cleanly.
   Acquire (S, Port);
   Enable_Loopback (S, False);                         --  off; use a real pad
   Configure_Pins (S, Tx => Inv_Pad, Rx => Inv_Pad);   --  single-pad loopback
   Set_Inversion (S, Tx => True);
   Write (S, Inv_Tx);
   Read  (S, Inv_Rx, Got);
   Release (S);
   Tx_Only_Broke := Got /= Inv_Tx'Length;
   for I in Inv_Tx'First .. Inv_Tx'First + Got - 1 loop
      if Inv_Rx (I) /= Inv_Tx (I) then
         Tx_Only_Broke := True;       --  any deviation = link broke (as expected)
      end if;
   end loop;

   --  TX and RX both inverted -> ends agree again -> clean round-trip.
   Acquire (S, Port);
   Set_Inversion (S, Tx => True, Rx => True);
   Write (S, Inv_Tx);
   Read  (S, Inv_Rx, Got2);
   Release (S);
   Tx_Rx_Match := Got2 = Inv_Tx'Length;
   for I in Inv_Tx'Range loop
      if Inv_Rx (I) /= Inv_Tx (I) then
         Tx_Rx_Match := False;
      end if;
   end loop;

   Invert (Boolean'Pos (Tx_Only_Broke), Boolean'Pos (Tx_Rx_Match),
           Boolean'Pos (Tx_Only_Broke and Tx_Rx_Match));

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
