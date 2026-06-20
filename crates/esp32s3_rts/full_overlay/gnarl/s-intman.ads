------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . I N T E R R U P T _ M A N A G E M E N T
--  S p e c
------------------------------------------------------------------------------
--  Bareboard implementation for the ESP32-S3 full-tasking runtime.  On a
--  hosted target this maps to POSIX signals; on the bareboard the GNARL only
--  needs the Interrupt_ID type and the Abort_Task_Interrupt designation.
--  Asynchronous task abort (which would wire Abort_Task_Interrupt to a real
--  reserved interrupt / cross-core poke) is the M5 frontier and is not yet
--  implemented; Abort_Task_Interrupt is a placeholder until then.
------------------------------------------------------------------------------

package System.Interrupt_Management is
   pragma Preelaborate;

   type Interrupt_ID is new Integer range 0 .. 255;

   type Interrupt_Set is array (Interrupt_ID) of Boolean;

   Abort_Task_Interrupt : Interrupt_ID := 0;
   --  Placeholder until M5 wires abort to a reserved bareboard interrupt.

   Keep_Unmasked : Interrupt_Set := [others => False];
   Reserve       : Interrupt_Set := [others => False];

   procedure Initialize;

end System.Interrupt_Management;
