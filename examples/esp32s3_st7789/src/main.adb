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
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.ST7789;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package LCD renames ESP32S3.ST7789;

   procedure Banner;       pragma Import (C, Banner, "native_st_banner");
   procedure Step (Code : int);
                           pragma Import (C, Step,   "native_st_step");
   procedure Done;         pragma Import (C, Done,   "native_st_done");

   Backlight : constant ESP32S3.GPIO.Pin_Id := 6;

   Dev : LCD.Device;
   S   : LCD.Session;

   procedure Hold is
   begin
      delay until Clock + Milliseconds (800);
   end Hold;

begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  Backlight is the example's job, not the driver's: drive IO6 high.
   ESP32S3.GPIO.Configure (Backlight, Mode => ESP32S3.GPIO.Output);
   ESP32S3.GPIO.Set (Backlight);

   LCD.Setup (Dev, Sclk => 12, Mosi => 13, DC => 16, CS => 10);   --  240x240 @ 40 MHz
   Step (0);

   LCD.Acquire (S, Dev);          --  protect the display for the whole demo
   LCD.Init (S);
   Step (1);

   --  Full-screen colour fills (each locks the SPI host only for its transfer).
   LCD.Fill (S, LCD.Red);   Step (2); Hold;
   LCD.Fill (S, LCD.Green); Step (3); Hold;
   LCD.Fill (S, LCD.Blue);  Step (4); Hold;

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
   Step (5); Hold;

   --  A centred white box on a dark background.
   LCD.Fill (S, LCD.RGB (16, 16, 32));
   LCD.Fill_Rect (S, X => 70, Y => 70, W => 100, H => 100, C => LCD.White);
   LCD.Fill_Rect (S, X => 90, Y => 90, W => 60,  H => 60,  C => LCD.RGB (255, 128, 0));
   Step (6); Hold;

   LCD.Release (S);
   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
