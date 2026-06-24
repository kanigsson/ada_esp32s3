--  Drive a string of TX1812 addressable RGB LEDs on IO48 via the RMT peripheral.
--
--  The string (64 LEDs) is declared once at library level in LED_Panel, so its
--  ~6.4 KiB of buffers are reserved at elaboration (see LED_Panel).  Each frame
--  here sets ALL 64 pixels to one colour and Shows it; the full 1536-symbol
--  frame is streamed out IO48 by the RMT wrap re-fill (Phase 2), since it far
--  exceeds the 48-symbol RMT RAM.
--
--  With no physical string attached, the board's on-board LED on IO48 is just
--  pixel 1 of the chain -- so it cycles red -> green -> blue -> white -> off,
--  confirming the stream actually transmits.  Wire a real string into IO48 and
--  all 64 light up.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.TX1812;
with LED_Panel;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;              pragma Import (C, Banner, "native_led_banner");
   procedure Acquired (Ok : int); pragma Import (C, Acquired, "native_led_acquired");
   procedure Name (Idx : int);    pragma Import (C, Name, "native_led_color");

   package LED renames ESP32S3.TX1812;

   Data_Pin : constant ESP32S3.GPIO.Pin_Id := 48;
   Lvl      : constant := 48;                 --  moderate brightness (0 .. 255)

   Colors : constant array (0 .. 4) of LED.Color :=
     (0 => (R => Lvl, G => 0,   B => 0),      --  red
      1 => (R => 0,   G => Lvl, B => 0),      --  green
      2 => (R => 0,   G => 0,   B => Lvl),    --  blue
      3 => (R => Lvl, G => Lvl, B => Lvl),    --  white
      4 => LED.Off);                          --  off
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  Acquire the channel BEFORE driving the string.  Channel 0, default 1 RMT
   --  block (the wrap path handles all 64 LEDs); pass Blocks => 4 to push up to
   --  ~7 LEDs out in one shot without wrap.
   LED.Acquire (LED_Panel.Panel, Pin => Data_Pin, Channel => 0);
   Acquired (Boolean'Pos (LED.Is_Valid (LED_Panel.Panel)));
   if not LED.Is_Valid (LED_Panel.Panel) then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   loop
      for I in Colors'Range loop
         LED.Set_All (LED_Panel.Panel, Colors (I));   --  all 64 pixels
         LED.Show (LED_Panel.Panel);                  --  stream the whole frame
         Name (int (I));
         delay until Clock + Milliseconds (600);
      end loop;
   end loop;
end Main;
