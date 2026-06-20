package Blink is
   pragma Elaborate_Body;
   --  Library-level protected objects whose handlers attach to the L2 and L3
   --  device interrupts (see the body).  Counts are read by the main victim.
   function L2_Count return Integer;
   function L3_Count return Integer;
end Blink;
