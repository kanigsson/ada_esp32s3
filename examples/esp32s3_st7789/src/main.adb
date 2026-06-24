--  ST7789 240x240 SPI display driver demo on the bare-metal ESP32-S3 (no
--  FreeRTOS, no IDF).  Exercises the reusable HAL driver (ESP32S3.ST7789)
--  against a real panel:
--
--     SPI2:  SCLK=IO12  MOSI=IO13   control: DC=IO16  CS=IO10   (no RESET)
--     backlight = IO6  (driven HERE by the example, NOT the driver)
--
--  It holds ONE Session for the whole demo -- so the display is protected
--  against other tasks the entire time -- while each Fill / Fill_Rect below
--  locks the SPI host only for its own transfer and frees it again (the
--  two-level locking this driver is built around).  The panel is the output;
--  the console just narrates the steps (SPI is write-only -- nothing to read).
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.Log;       use ESP32S3.Log;
with ESP32S3.ST7789;
with ESP32S3.ST7789.Text;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package LCD renames ESP32S3.ST7789;

   --  One step line, e.g. "[lcd] init".
   procedure Step (Name : String) is
   begin
      Put ("[lcd] ");
      Put_Line (Name);
   end Step;

   Backlight : constant ESP32S3.GPIO.Pin_Id := 6;

   Dev : LCD.Device;
   S   : LCD.Session;

   procedure Hold is
   begin
      delay until Clock + Milliseconds (800);
   end Hold;

begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[lcd] ST7789 240x240 SPI display demo "
             & "(SPI2 sclk=12 mosi=13 dc=16 cs=10, bl=6)");

   --  Backlight is the example's job, not the driver's: drive IO6 high.
   ESP32S3.GPIO.Configure (Backlight, Mode => ESP32S3.GPIO.Output);
   ESP32S3.GPIO.Set (Backlight);

   LCD.Setup (Dev, Sclk => 12, Mosi => 13, DC => 16, CS => 10);   --  240x240 @ 40 MHz
   Step ("backlight + setup");

   LCD.Acquire (S, Dev);          --  protect the display for the whole demo
   LCD.Init (S);
   Step ("init");

   --  Full-screen colour fills (each locks the SPI host only for its transfer).
   LCD.Fill (S, LCD.Red);   Step ("fill red");   Hold;
   LCD.Fill (S, LCD.Green); Step ("fill green"); Hold;
   LCD.Fill (S, LCD.Blue);  Step ("fill blue");  Hold;

   --  Eight vertical colour bars (30 px each across the 240-wide panel).
   declare
      Bars : constant array (0 .. 7) of LCD.Color :=
        (LCD.Red, LCD.Green, LCD.Blue, LCD.White,
         LCD.RGB (255, 255, 0), LCD.RGB (0, 255, 255),
         LCD.RGB (255, 0, 255), LCD.Black);
   begin
      for I in Bars'Range loop
         LCD.Fill_Rect (S, X => I * 30, Y => 0, W => 30, H => 240,
                        C => Bars (I));
      end loop;
   end;
   Step ("colour bars"); Hold;

   --  A centred white box on a dark background.
   LCD.Fill (S, LCD.RGB (16, 16, 32));
   LCD.Fill_Rect (S, X => 70, Y => 70, W => 100, H => 100, C => LCD.White);
   LCD.Fill_Rect (S, X => 90, Y => 90, W => 60,  H => 60,  C => LCD.RGB (255, 128, 0));
   Step ("centre box"); Hold;

   --  Text: 5x7 font at three scales on a dark background (.Text child layer).
   LCD.Fill (S, LCD.RGB (0, 0, 32));
   LCD.Text.Draw_Text (S, X => 6,  Y => 16,  Str => "ESP32-S3 + Ada",
                       FG => LCD.White, BG => LCD.RGB (0, 0, 32));
   LCD.Text.Draw_Text (S, X => 6,  Y => 60,  Str => "ST7789",
                       FG => LCD.RGB (0, 255, 0), BG => LCD.RGB (0, 0, 32),
                       Scale => 3);
   LCD.Text.Draw_Text (S, X => 6,  Y => 120, Str => "40 MHz SPI" & Character'Val (10)
                                                     & "240x240" & Character'Val (10)
                                                     & "write-only",
                       FG => LCD.RGB (255, 200, 0), BG => LCD.RGB (0, 0, 32),
                       Scale => 2);
   Step ("text"); Hold;

   LCD.Release (S);
   Put_Line ("[lcd] done -- check the panel.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
