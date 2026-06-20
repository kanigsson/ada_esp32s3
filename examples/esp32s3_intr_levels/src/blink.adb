pragma Warnings (Off);
with Ada.Interrupts.Names;
with System;

--  L2/L3 interrupt handlers for the vector regression test.  Two library-level
--  protected objects attach to the L2 (Device_L2_0 = CPU_INT 19) and L3
--  (Device_L3_0 = CPU_INT 23) device interrupts.  example.adb fires them via the
--  FROM_CPU matrix sources; each handler clears its (level-triggered) source and
--  counts.  This exercises __gnat_level2_vector / __gnat_level3_vector (whose
--  XT_STK frame build now masks debug across the per-task stack watchpoint).
package body Blink is

   procedure Clear_L2;
   pragma Import (C, Clear_L2, "ada_clear_l2");
   procedure Clear_L3;
   pragma Import (C, Clear_L3, "ada_clear_l3");

   protected L2_PO with
     Interrupt_Priority => Ada.Interrupts.Names.Device_L2_Priority
   is
      function Count return Integer;
   private
      procedure Handle;
      pragma Attach_Handler (Handle, Ada.Interrupts.Names.Device_L2_0);
      N : Integer := 0;
   end L2_PO;

   protected body L2_PO is
      procedure Handle is
      begin
         Clear_L2;
         N := N + 1;
      end Handle;
      function Count return Integer is (N);
   end L2_PO;

   protected L3_PO with
     Interrupt_Priority => Ada.Interrupts.Names.Device_L3_Priority
   is
      function Count return Integer;
   private
      procedure Handle;
      pragma Attach_Handler (Handle, Ada.Interrupts.Names.Device_L3_0);
      N : Integer := 0;
   end L3_PO;

   protected body L3_PO is
      procedure Handle is
      begin
         Clear_L3;
         N := N + 1;
      end Handle;
      function Count return Integer is (N);
   end L3_PO;

   function L2_Count return Integer is (L2_PO.Count);
   function L3_Count return Integer is (L3_PO.Count);

end Blink;
