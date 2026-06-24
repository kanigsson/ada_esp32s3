--  TCA9555 16-bit I2C GPIO-expander driver demo on the bare-metal ESP32-S3 (no
--  FreeRTOS, no IDF).  Exercises the reusable HAL driver (ESP32S3.TCA9555)
--  against a real expander at 0x20 on the I2C bus (SDA = IO8, SCL = IO7).
--
--  It holds ONE Session for the whole test -- so the expander is protected
--  against other tasks the entire time -- while each register read / write
--  below locks the I2C host only for its own transaction and frees it again
--  (the two-level locking this driver is built around).
--
--  This board's expander pins are wired to external circuitry (the input port
--  reads a fixed pattern), so the demo deliberately NEVER drives a pin: it
--  leaves every pin an input and proves the driver another way --
--    probe     read the input port (comms check; shows the external levels).
--    out-reg   write the output REGISTER and read it back (it stores the value
--              even while the pins stay inputs, so nothing is driven).
--    pin       per-pin read-modify-write of the output register (the RMW path
--              the held Session protects).
--    pol-reg   write the polarity-inversion register and read it back.
--  To actually drive outputs (e.g. LEDs on free pins), call Set_Directions to
--  make them outputs and Write_Port / Write_Pin -- omitted here on purpose.
--  (Note: on this board's part the polarity register accepts writes but the chip
--  does not actually invert the input -- a quirk of the part, not the driver.)
--
--  Report goes through the ROM printf glue; the Ada driver does all the I2C work.
with Interfaces;     use Interfaces;
with Ada.Real_Time;  use Ada.Real_Time;

with ESP32S3.Log;    use ESP32S3.Log;
with ESP32S3.TCA9555;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package GPX renames ESP32S3.TCA9555;
   use type GPX.Status;
   use type GPX.Port_Value;

   --  Low 16 bits of a port value as an Unsigned_32, for "0x%04x" hex output.
   function U16 (V : GPX.Port_Value) return Unsigned_32 is
     (Unsigned_32 (V) and 16#FFFF#);

   --  "[gpio] probe   : inputs=0x%04x  %s\n" (ok ? "(present)" : "(no ACK!)").
   procedure Probe (Inputs : GPX.Port_Value; Ok : Boolean) is
   begin
      Put ("[gpio] probe   : inputs=0x");
      Put_Hex (U16 (Inputs), 4);
      Put ("  ");
      Put_Line (if Ok then "(present)" else "(no ACK!)");
   end Probe;

   --  "[gpio] %-7s : wrote=0x%04x read=0x%04x  %s\n" for out-reg / pol-reg
   --  (Name is "out-reg" or "pol-reg", both 7 chars so no padding is needed).
   procedure Reg_Line (Name : String; Wrote, Got : GPX.Port_Value; Ok : Boolean)
   is
   begin
      Put ("[gpio] ");
      Put (Name);
      Put (" : wrote=0x");
      Put_Hex (U16 (Wrote), 4);
      Put (" read=0x");
      Put_Hex (U16 (Got), 4);
      Put ("  ");
      Put_Line (if Ok then "PASS" else "FAIL");
   end Reg_Line;

   --  "[gpio] pin %-2d  : set=%d  out-bit=%d  %s\n" (left-justified to width 2,
   --  so a single-digit pin gets one trailing space).
   procedure Pin_R (Pin, Wrote, Got : Integer; Ok : Boolean) is
   begin
      Put ("[gpio] pin ");
      Put (Pin);
      if Pin in 0 .. 9 then
         Put (" ");
      end if;
      Put ("  : set=");
      Put (Wrote);
      Put ("  out-bit=");
      Put (Got);
      Put ("  ");
      Put_Line (if Ok then "PASS" else "FAIL");
   end Pin_R;

   Dev  : GPX.Device;
   S    : GPX.Session;
   St   : GPX.Status;
   V    : GPX.Port_Value;
   Orig : GPX.Port_Value;

   Bit5 : constant GPX.Port_Value := 2 ** 5;
   Patterns : constant array (1 .. 2) of GPX.Port_Value :=
     (16#A55A#, 16#5AA5#);

   procedure Gap is
   begin
      delay until Clock + Milliseconds (30);   --  let the console FIFO drain
   end Gap;

begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[gpio] TCA9555 16-bit I2C GPIO expander demo "
             & "(0x20, SDA=IO8 SCL=IO7)");

   GPX.Setup (Dev, Addr => 0, Sda => 8, Scl => 7);
   GPX.Acquire (S, Dev);                    --  hold the expander for the test

   --  Force every pin to an input -- a known, non-driving state (independent of
   --  whatever the registers held before) so nothing fights the external wiring.
   GPX.Set_Directions (S, Inputs => 16#FFFF#, Result => St);

   --  probe: read the input port.
   GPX.Read_Port (S, Orig, St);
   Gap; Probe (Orig, St = GPX.OK);
   if St /= GPX.OK then
      Put_Line ("[gpio] no TCA9555 found at 0x20 -- check wiring/power.");
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   --  out-reg round-trip: write the output register, read it back.  Pins stay
   --  inputs, so nothing is driven -- this checks the write + read path only.
   for P of Patterns loop
      GPX.Write_Port (S, P, St);
      if St = GPX.OK then
         GPX.Read_Outputs (S, V, St);
      end if;
      Gap;
      Reg_Line ("out-reg", P, V, St = GPX.OK and then V = P);
   end loop;

   --  per-pin RMW of the output register.
   GPX.Write_Pin (S, 5, GPX.High, St);
   GPX.Read_Outputs (S, V, St);
   Gap;
   Pin_R (5, 1, Boolean'Pos ((V and Bit5) /= 0),
          St = GPX.OK and then (V and Bit5) /= 0);

   GPX.Write_Pin (S, 5, GPX.Low, St);
   GPX.Read_Outputs (S, V, St);
   Gap;
   Pin_R (5, 0, Boolean'Pos ((V and Bit5) /= 0),
          St = GPX.OK and then (V and Bit5) = 0);

   --  polarity-inversion register round-trip (write then read back).
   GPX.Set_Polarity (S, 16#A55A#, St);
   if St = GPX.OK then
      GPX.Read_Polarity (S, V, St);
   end if;
   Gap;
   Reg_Line ("pol-reg", 16#A55A#, V, St = GPX.OK and then V = 16#A55A#);
   GPX.Set_Polarity (S, 0, St);             --  restore normal polarity

   GPX.Release (S);
   Gap; Put_Line ("[gpio] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
