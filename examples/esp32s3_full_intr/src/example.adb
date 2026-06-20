pragma Warnings (Off);
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;
with Blink;

--  Full-profile interrupt-attach regression test (L2 / L3 / L5).
--
--  This is the FULL-profile twin of esp32s3_intr_levels.  Its purpose is to
--  prove that the portable Ada interrupt layer -- pragma Attach_Handler on a
--  protected object, via Ada.Interrupts -- now WORKS under ESP32S3_RTS_PROFILE
--  =full.  Until the bareboard full System.Interrupts was implemented
--  (full_overlay/gnarl/s-interr.{ads,adb}), building Blink on full failed with
--  "System.Interrupts.Register_Interrupt_Handler not defined".  Blink's two
--  library-level interrupt POs (see blink.adb) attach with pragma Attach_Handler
--  exactly as on embedded; if this links and the counts climb on hardware, the
--  full dynamic interrupt machinery is in place.
--
--  Test body (identical to the embedded version, so it also re-checks vector
--  context preservation under the full kernel): a low-priority "victim" holds
--  register-resident state across a tight loop -- four FP accumulators (the
--  identity X := X*Lm*Li with Lm/Li read once from Volatile cells, so they stay
--  in F registers with NO in-loop memory traffic) plus a THREADPTR sentinel.
--  Each batch it fires the L2 and L3 device interrupts (preempting it through
--  __gnat_level2_vector / __gnat_level3_vector); the L5 tick preempts it
--  asynchronously throughout.  If any vector failed to save/restore the
--  preempted context, an accumulator or THREADPTR comes back wrong and we log
--  911.
--
--  Console ([intr] <n>): per clean batch, 1xxxxx = L2 handler count,
--  2xxxxx = L3 handler count, 3xxxxx = clean-batch counter.  L2/L3 must climb
--  together with the clean counter and there must be NO 911.
procedure Example is
   procedure Log (Marker : Interfaces.C.int);
   pragma Import (C, Log, "ada_log");
   procedure Setup;   pragma Import (C, Setup,   "ada_setup_l2l3");
   procedure Fire_L2; pragma Import (C, Fire_L2, "ada_fire_l2");
   procedure Fire_L3; pragma Import (C, Fire_L3, "ada_fire_l3");
   function  Get_TP return Interfaces.C.unsigned;
   pragma Import (C, Get_TP, "ada_get_tp");
   procedure Set_TP (V : Interfaces.C.unsigned);
   pragma Import (C, Set_TP, "ada_set_tp");

   Sentinel : constant Interfaces.C.unsigned := 16#DEAD_0001#;
   VM : Float := 2.0 with Volatile;
   VI : Float := 0.5 with Volatile;
   Lm : constant Float := VM;
   Li : constant Float := VI;
   X1 : Float := 1.0;
   X2 : Float := 2.0;
   X3 : Float := 3.0;
   X4 : Float := 4.0;
   Iter : Interfaces.C.int := 0;
begin
   Setup;                       --  route FROM_CPU_0/1 -> CPU_INT 19/23 (L2/L3)
   Set_TP (Sentinel);
   loop
      for I in 1 .. 400_000 loop
         X1 := X1 * Lm * Li;
         X2 := X2 * Lm * Li;
         X3 := X3 * Lm * Li;
         X4 := X4 * Lm * Li;
         if I mod 100_000 = 0 then
            Fire_L2;
            Fire_L3;
         end if;
      end loop;

      if X1 /= 1.0 or else X2 /= 2.0 or else X3 /= 3.0 or else X4 /= 4.0
        or else Get_TP /= Sentinel
      then
         Log (911);                                           --  CONTEXT LOST
         X1 := 1.0; X2 := 2.0; X3 := 3.0; X4 := 4.0;
         Set_TP (Sentinel);
      else
         Iter := Iter + 1;
         Log (100_000 + Interfaces.C.int (Blink.L2_Count));   --  1xxxxx = L2
         Log (200_000 + Interfaces.C.int (Blink.L3_Count));   --  2xxxxx = L3
         Log (300_000 + Iter);                                --  3xxxxx = clean
      end if;
   end loop;
end Example;
