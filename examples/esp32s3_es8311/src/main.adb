--  ES8311 audio-codec test: bring the codec up for output and play a gapless
--  440 Hz sine on its DAC.  Control is over I2C (SDA=IO8, SCL=IO7); audio is
--  over I2S (MCLK=IO1, SCLK=IO2, LRCK=IO4, DSDIN=IO5; the codec's ASDOUT=IO3 is
--  unused for output).  The codec is an I2S slave clocked from the ESP's
--  MCLK = 256*fs.
--
--  For a CLICK-FREE tone we play one buffer holding a whole number of wave
--  periods on a self-looping DMA (Play_Continuous): the hardware replays it
--  forever with no inter-buffer gap and no CPU involvement.  440 Hz at 16 kHz
--  is 400/11 samples per cycle, so 400 frames span exactly 11 cycles and the
--  loop wraps seamlessly (sample 400 would equal sample 0).
with Interfaces;    use Interfaces;
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.I2C;
with ESP32S3.I2S;
with ESP32S3.ES8311;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;            pragma Import (C, Banner, "native_es_banner");
   procedure Init_R (Ok : int); pragma Import (C, Init_R, "native_es_init");
   procedure Playing;           pragma Import (C, Playing, "native_es_playing");

   Rate : constant := 16_000;          --  sample rate (Hz)
   Freq : constant := 440;             --  tone frequency (Hz)
   --  Peak amplitude ~-1 dBFS (near full-scale 32767, a hair of headroom).  With
   --  the codec at unity gain (see Volume below) loudness comes from this
   --  full-scale digital signal, which the DAC reproduces cleanly.  The Bhaskara
   --  sine peaks at exactly Amp (<= Amp everywhere), so this never overflows
   --  Integer_16 (the Amp*16*P intermediate is computed in 64-bit).
   Amp  : constant := 30_000;

   --  One seamless loop = the fewest whole cycles that are an integer number of
   --  samples.  gcd(16000, 440) = 40, so 11 cycles = 400 frames exactly.
   Cycles : constant := Freq / 40;          --  11
   Frames : constant := Rate / 40;          --  400 (= Cycles * Rate / Freq)
   Buf_Bytes : constant := Frames * 4;      --  1600 bytes (stereo 16-bit) <= 4095

   type Sample is new Interfaces.Integer_16;

   --  One full cycle of sine in Frames entries (Bhaskara I integer approx:
   --  sin(pi*t) ~ 16 t(1-t) / (5 - 4 t(1-t))), used as a 400-point unit circle.
   Cycle : array (0 .. Frames - 1) of Sample;

   procedure Build_Cycle is
      Half : constant := Frames / 2;          --  200 (one half-cycle)
      V    : Integer;
   begin
      for K in 0 .. Half - 1 loop
         declare
            P : constant Integer := K * (Half - K);
            --  64-bit intermediate: Amp*16*P reaches ~5.2e9 at full scale,
            --  which overflows 32-bit Integer.
            Num : constant Long_Long_Integer :=
              Long_Long_Integer (Amp) * 16 * Long_Long_Integer (P);
            Den : constant Long_Long_Integer :=
              Long_Long_Integer (5 * Half * Half - 4 * P);
         begin
            V := Integer (Num / Den);
         end;
         Cycle (K)        :=  Sample (V);
         Cycle (K + Half) := -Sample (V);
      end loop;
   end Build_Cycle;

   --  One streamed buffer of stereo 16-bit frames (the mono codec uses the left
   --  slot; we duplicate into both).  Lives in Main's frame (internal SRAM) and
   --  stays valid for the life of the program, which the looping DMA requires.
   type Frame is record
      L, R : Sample;
   end record;
   for Frame'Size use 32;
   type Buffer is array (0 .. Frames - 1) of Frame;
   Buf : Buffer;

begin
   delay until Clock + Milliseconds (200);
   Banner;
   Build_Cycle;

   --  Frame i is at phase Cycles*i cycles: index the unit circle at
   --  (Cycles*i) mod Frames so the 400 frames carry exactly 11 cycles.
   for I in Buf'Range loop
      declare
         S : constant Sample := Cycle ((Cycles * I) mod Frames);
      begin
         Buf (I) := (L => S, R => S);
      end;
   end loop;

   declare
      Ok    : Boolean;
      Audio : ESP32S3.ES8311.Output;
   begin
      ESP32S3.ES8311.Setup
        (I2C_Bus => ESP32S3.I2C.I2C0,
         Sda     => 8,  Scl   => 7,
         Port    => ESP32S3.I2S.I2S0,
         Mclk    => 1,  Sclk  => 2,  Lrck => 4,  Dsdin => 5,
         --  Volume 75 % -> DAC reg 0x32 = 0xBF ~ 0 dB (unity).  Higher values
         --  are POSITIVE gain (0xFF ~ +32 dB) and clip; loudness here comes from
         --  the near-full-scale digital sine, not codec boost.
         Sample_Rate => Rate, Volume => 75, Ok => Ok);
      Init_R (Boolean'Pos (Ok));
      if not Ok then
         loop delay until Clock + Seconds (3600); end loop;
      end if;

      Playing;
      ESP32S3.ES8311.Acquire (Audio);          --  hold the audio port
      --  Kick the gapless loop once; the DMA replays Buf forever, click-free.
      ESP32S3.ES8311.Play_Continuous (Audio, Buf'Address, Buf_Bytes);
      loop
         delay until Clock + Seconds (3600);   --  tone runs with no CPU help
      end loop;
   end;
end Main;
