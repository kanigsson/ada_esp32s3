--  Drive a single TX1812 addressable RGB LED on IO48 via the RMT peripheral.
--  Acquires an RMT transmit channel (the LED handle owns it and releases it on
--  scope exit), then cycles the LED red -> green -> blue -> white -> off,
--  printing each colour so the serial log can be matched to what you see.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.TX1812;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;             pragma Import (C, Banner, "native_led_banner");
   procedure Acquired (Ok : int); pragma Import (C, Acquired, "native_led_acquired");
   procedure Name (Idx : int);   pragma Import (C, Name, "native_led_color");

   package LED renames ESP32S3.TX1812;

   Data_Pin : constant ESP32S3.GPIO.Pin_Id := 48;
   Lvl      : constant := 48;                 --  moderate brightness (0..255)

   --  Buffered handle for one LED; finalization releases the RMT channel.
   S : LED.Strip (Count => 1);

   Colors : constant array (0 .. 4) of LED.Color :=
     (0 => (R => Lvl, G => 0,   B => 0),      --  red
      1 => (R => 0,   G => Lvl, B => 0),      --  green
      2 => (R => 0,   G => 0,   B => Lvl),    --  blue
      3 => (R => Lvl, G => Lvl, B => Lvl),    --  white
      4 => LED.Off);                          --  off
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  Acquire the channel BEFORE driving the LED.
   LED.Acquire (S, Pin => Data_Pin, Channel => 0);
   Acquired (Boolean'Pos (LED.Is_Valid (S)));
   if not LED.Is_Valid (S) then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   loop
      for I in Colors'Range loop
         LED.Set (S, Index => 1, C => Colors (I));
         LED.Show (S);
         Name (int (I));
         delay until Clock + Milliseconds (600);
      end loop;
   end loop;
end Main;
