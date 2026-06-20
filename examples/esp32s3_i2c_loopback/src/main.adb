--  Ada I2C MASTER hardware self-test on the bare-metal ESP32-S3 (no FreeRTOS,
--  no IDF) -- exercises the reusable HAL master driver (ESP32S3.I2C) with NO
--  external wiring and no device on the bus.
--
--  Why no internal master<->slave loopback?  I2C SDA is a bidirectional
--  open-drain (wired-AND) node: both ends must DRIVE and READ the same wire.
--  The ESP32-S3 GPIO matrix gives each pad exactly one output source, so it
--  cannot wire-AND two on-chip controllers onto one pad -- there is no way to
--  internally connect two I2C controllers into a working bus.  (Cross-coupling
--  two pads breaks the master's mandatory write-readback; a single shared pad
--  breaks the slave's mandatory ACK.)  Verifying the READ direction and ACK
--  handshake therefore needs a real shared bus: an external device, or a jumper
--  tying two pads together.  See the README.
--
--  What this self-test proves on silicon, using only the master + its own pads:
--    test0  write to an ABSENT address (ACK-checked): the master issues a real
--           START, clocks the 7-bit address, samples the (absent) ACK, sees
--           NACK and ends with a STOP -> Success = False.  PASS = NACK detected.
--    test1  multi-byte write to that address with ACK-checking OFF: the master
--           clocks the address + 5 data bytes + STOP to completion regardless of
--           ACK -> Success = True.  PASS = the full transaction completes.
--
--  Together these exercise START/STOP, 7-bit addressing, the command-sequence
--  FSM, multi-byte FIFO transmit, the bus timing, and ACK/NACK detection.
--  Report goes through the ROM printf glue (the reliable console path here).
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.I2C;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the test runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use ESP32S3.I2C;

   procedure Banner;
   pragma Import (C, Banner, "native_i2c_banner");
   procedure Verdict (Test, Ok : int);
   pragma Import (C, Verdict, "native_i2c_verdict");
   procedure Done;
   pragma Import (C, Done, "native_i2c_done");

   Host : constant I2C_Host := I2C0;

   --  Two free general-purpose pads (avoid 26..32 = flash / PSRAM); the master's
   --  SDA and SCL each loop their own output back to their own input.
   Sda_Pad : constant := 4;
   Scl_Pad : constant := 6;

   --  No device lives at this address on the (empty) bus.
   Absent : constant Slave_Address := 16#55#;

   Payload : constant Byte_Array := (16#A5#, 16#3C#, 16#01#, 16#FE#, 16#7D#);

   S  : Session;
   Ok : Boolean;
begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Banner;

   Setup (Host, Clock_Hz => 100_000);
   Configure_Pins (Host, Scl => Scl_Pad, Sda => Sda_Pad);

   --  test0: ACK-checked write to an absent address -> expect NACK.
   Acquire (S, Host);
   Write (S, Absent, (1 => 16#00#), Ok);
   Release (S);
   Verdict (0, Boolean'Pos (not Ok));        --  PASS = NACK correctly detected

   --  test1: multi-byte write, ACK-checking off -> expect completion.
   Acquire (S, Host);
   Write (S, Absent, Payload, Ok, Check_Ack => False);
   Release (S);
   Verdict (1, Boolean'Pos (Ok));            --  PASS = full transaction completed

   --  test2: the Session is a controlled type, so it auto-releases the host when
   --  it leaves scope -- even via an exception.  Acquire then raise inside a
   --  block; if Finalize released the host, the next Acquire succeeds.  (A leaked
   --  lock would block the second Acquire forever, so reaching the verdict at all
   --  -- with Reacquired True -- is the proof.)
   declare
      Reacquired : Boolean := False;
   begin
      begin
         declare
            T : Session;
         begin
            Acquire (T, Host);
            raise Program_Error;          --  fault before any explicit Release
         end;                             --  Finalize (T) -> Release on unwind
      exception
         when others => null;
      end;

      declare
         T : Session;
      begin
         Acquire (T, Host);               --  would deadlock if the lock leaked
         Reacquired := True;
         Release (T);
      end;
      Verdict (2, Boolean'Pos (Reacquired));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
