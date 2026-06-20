------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . B I N D G E N _ G L O B A L S
--  B o d y
------------------------------------------------------------------------------

with System.Secondary_Stack;
with System.Task_Primitives.Operations;

package body System.Bindgen_Globals is

   --  Environment-task priority / CPU.  The binder writes -1 (unspecified)
   --  unless pragma Priority / CPU is used on the main subprogram.

   Main_Priority : Integer := -1;
   pragma Export (C, Main_Priority, "__gl_main_priority");

   Main_CPU : Integer := -1;
   pragma Export (C, Main_CPU, "__gl_main_cpu");

   --  Secondary stack of the calling task (read by System.Soft_Links).

   function Get_Sec_Stack return System.Secondary_Stack.SS_Stack_Ptr;
   pragma Export (C, Get_Sec_Stack, "__gnat_get_secondary_stack");

   function Get_Sec_Stack return System.Secondary_Stack.SS_Stack_Ptr is
   begin
      return System.Task_Primitives.Operations.Self
               .Common.Compiler_Data.Sec_Stack_Ptr;
   end Get_Sec_Stack;

   --  Structured exception handling: not used on the bareboard.

   function Install_SEH_Handler (EH : System.Address) return Integer;
   pragma Export (C, Install_SEH_Handler, "__gnat_install_SEH_handler");

   function Install_SEH_Handler (EH : System.Address) return Integer is
      pragma Unreferenced (EH);
   begin
      return 0;
   end Install_SEH_Handler;

   --  Per-interrupt handling state (pragma Interrupt_State).  No interrupt is
   --  reserved at bind time on this runtime; 'n' = no user-specified state.

   function Get_Interrupt_State (Interrupt : Integer) return Character;
   pragma Export (C, Get_Interrupt_State, "__gnat_get_interrupt_state");

   function Get_Interrupt_State (Interrupt : Integer) return Character is
      pragma Unreferenced (Interrupt);
   begin
      return 'n';
   end Get_Interrupt_State;

end System.Bindgen_Globals;
