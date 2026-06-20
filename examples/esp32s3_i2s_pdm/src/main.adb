--  Ada I2S PDM microphone capture demo on the bare-metal ESP32-S3
--  ==============================================================
--  Exercises the I2S driver's PDM mode (ESP32S3.I2S, Mode => PDM): the hardware
--  PDM->PCM decimator on the receive side -- the path a digital PDM microphone
--  (or a PDM-output ADC) uses.  In PDM mode the ESP is the clock master: it
--  drives the mic clock out on the WS pin and reads the mic's 1-bit pulse-density
--  stream in on the data pin; the hardware decimates it back to PCM, which the
--  DMA delivers as ordinary 16-bit samples.
--
--  THIS DEMO NEEDS EXTERNAL HARDWARE.  PDM cannot be self-tested on-chip: there
--  is no internal loopback for the converters (SIG_LOOPBACK only shares the
--  standard-I2S WS+BCK), and the decimator's mandatory high-pass filter strips
--  DC -- so any static level you could synthesise from a GPIO (a pull resistor or
--  a driven pin) is rejected and cannot stand in for a mic.  Genuine verification
--  needs a real PDM device producing a toggling bitstream.  Wire a PDM mic:
--
--      mic CLK  <-  GPIO 5   (Clk_Pin below -- the ESP drives this)
--      mic DATA ->  GPIO 6   (Data_Pin below)
--      mic SEL/L-R, VDD, GND per its datasheet
--
--  The demo captures several blocks and prints each block's peak-to-peak level,
--  so with a mic wired you can watch the level rise when you speak or tap it.
--  With no mic the input floats -- expect a railed/quiet reading.
with Interfaces;   use Interfaces;
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Unchecked_Conversion;

with ESP32S3.I2S;   use ESP32S3.I2S;
with ESP32S3.GPIO;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_pdm_banner");
   procedure Hint (Clk, Dat : int);
   pragma Import (C, Hint, "native_pdm_hint");
   procedure Block (Idx, Mn, Mx, Pp, Signal : int);
   pragma Import (C, Block, "native_pdm_block");
   procedure Done;
   pragma Import (C, Done, "native_pdm_done");

   --  PDM microphone pins (validated GPIO pins; the ESP drives Clk, reads Data).
   Clk_Pin  : constant ESP32S3.GPIO.Pin_Id := 5;
   Data_Pin : constant ESP32S3.GPIO.Pin_Id := 6;

   --  16-bit stereo PCM.  256 frames = 512 words = 1024 bytes (< 4095 DMA cap).
   Frames : constant := 256;
   Blocks : constant := 8;        --  capture this many, ~one block every 100 ms
   Floor  : constant := 1_500;    --  peak-to-peak above this == "signal present"
   subtype Sample_Index is Natural range 0 .. 2 * Frames - 1;
   type Samples is array (Sample_Index) of Unsigned_16;
   Rx : Samples := (others => 0);

   function To_Signed is
     new Ada.Unchecked_Conversion (Unsigned_16, Integer_16);
begin
   delay until Clock + Milliseconds (200);
   Banner;
   Hint (int (Clk_Pin), int (Data_Pin));

   Setup (I2S0, Sample_Rate => 16_000, Bits => Bits_16, Mode => PDM);
   --  PDM mic: clock OUT on Ws, data IN on Din (no BCK, no Dout for RX-only).
   Configure_Pins (I2S0, Bclk => No_Pin, Ws => ESP32S3.GPIO.Optional_Pin (Clk_Pin),
                   Dout => No_Pin, Din => ESP32S3.GPIO.Optional_Pin (Data_Pin));

   for B in 1 .. Blocks loop
      declare
         S  : Session;                    --  limited: cannot be copied/shared
         Mn : Integer := Integer (Integer_16'Last);
         Mx : Integer := Integer (Integer_16'First);
         V  : Integer;
      begin
         Acquire (S, I2S0);               --  suspends until the port is free
         Read (S, Rx'Address, Samples'Length * 2);

         --  Peak-to-peak of the recovered left channel (even index), skipping a
         --  few startup frames so the decimator settle isn't counted.
         for F in 8 .. Frames - 1 loop
            V  := Integer (To_Signed (Rx (2 * F)));
            Mn := Integer'Min (Mn, V);
            Mx := Integer'Max (Mx, V);
         end loop;

         --  "Signal" only if the capture both swings (> Floor) AND is not pinned
         --  at a rail -- a floating input (no mic) saturates the decimator near
         --  -32768, which must not read as a present signal.
         declare
            Railed : constant Boolean := Mn <= -32_000 or else Mx >= 32_000;
            Signal : constant Boolean := not Railed and then Mx - Mn > Floor;
         begin
            Block (int (B), int (Mn), int (Mx), int (Mx - Mn),
                   Boolean'Pos (Signal));
         end;
      end;                                --  S finalizes -> port released

      delay until Clock + Milliseconds (100);
   end loop;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
