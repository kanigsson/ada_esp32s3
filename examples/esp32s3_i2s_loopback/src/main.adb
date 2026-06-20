--  Ada I2S self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ==================================================================
--  Exercises the reusable HAL I2S driver (ESP32S3.I2S): bring I2S0 up as a
--  stereo master, loop its data-out line back into data-in through ONE GPIO pad
--  (the hardware SIG_LOOPBACK shares WS+BCK internally, so no wiring is needed),
--  then DMA a buffer out and capture it back full-duplex and compare it word for
--  word.  Also exercises the controlled (RAII) Session: Acquire on scope entry,
--  auto-Release on scope exit.  Report goes through the ROM printf glue.
with Interfaces;   use Interfaces;
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.I2S;   use ESP32S3.I2S;
with ESP32S3.GPIO;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the test runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_i2s_banner");
   procedure Result (N, Ok : int);
   pragma Import (C, Result, "native_i2s_result");
   procedure Done;
   pragma Import (C, Done, "native_i2s_done");

   Data_Pin : constant ESP32S3.GPIO.Pin_Id := 4;   --  loopback data pad (no wiring)

   --  16-bit stereo samples: 64 words = 32 stereo frames = 128 bytes.
   type Samples is array (0 .. 63) of Unsigned_16;
   Tx : Samples;
   Rx : Samples := (others => 0);
begin
   delay until Clock + Milliseconds (200);
   Banner;

   for I in Samples'Range loop
      Tx (I) := Unsigned_16 ((I * 1031 + 17) mod 65536);
   end loop;

   Setup (I2S0, Sample_Rate => 16_000, Bits => Bits_16);
   Enable_Loopback (I2S0, Pad => Data_Pin);

   declare
      S  : Session;                       --  limited: cannot be copied/shared
      Ok : Boolean := False;
   begin
      Acquire (S, I2S0);                  --  suspends until the port is free
      Transfer (S, Tx'Address, Rx'Address, Samples'Length * 2);
      Ok := (for all I in Samples'Range => Rx (I) = Tx (I));
      Result (Samples'Length, Boolean'Pos (Ok));
   end;                                   --  S finalizes -> port released

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
