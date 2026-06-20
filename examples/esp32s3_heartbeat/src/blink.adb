pragma Warnings (Off);
with Ada.Real_Time; use Ada.Real_Time;

package body Blink is
   task Periodic;
   task body Periodic is
      Next : Time := Clock + Milliseconds (100);
   begin
      loop
         delay until Next;
         Next := Next + Milliseconds (100);
      end loop;
   end Periodic;
end Blink;
