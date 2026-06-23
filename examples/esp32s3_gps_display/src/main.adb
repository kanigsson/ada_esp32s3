--  GPS-on-display demo on the bare-metal ESP32-S3 (no FreeRTOS, no IDF).
--  Combines two reusable HAL drivers:
--
--    * ESP32S3.GPS    -- task-driven NMEA receiver on UART0 (GPS TXD -> U0RXD =
--                        IO44, our U0TXD -> GPS RXD = IO43, 9600 baud).  A
--                        background task decodes the stream into a protected
--                        store; we just read the latest snapshot each second.
--    * ESP32S3.ST7789 -- 240x240 SPI panel (SPI2: SCLK=IO12 MOSI=IO13 DC=IO16
--                        CS=IO10) + its .Text 5x7 font layer.  Backlight IO6 is
--                        driven HERE, not by the driver.
--
--  Once a second we read Current_Time / Current_Position / Current_Fix and paint
--  UTC, latitude, longitude and fix status onto the panel.  The display Session
--  is held for the whole run (so no other task can corrupt the controller) while
--  each text update locks the SPI host only for its own transfers.  Lines are
--  padded to a fixed width so each opaque redraw overwrites the previous value.
--
--  The console mirrors every row pushed to the panel, so a live run can be
--  checked over serial too (the panel itself is write-only).
with System;
with Interfaces;   use type Interfaces.Integer_32;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.UART;
with ESP32S3.GPS;
with ESP32S3.ST7789;
with ESP32S3.ST7789.Text;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package GPS renames ESP32S3.GPS;
   package LCD renames ESP32S3.ST7789;
   use type GPS.Fix_Type;

   procedure Banner;        pragma Import (C, Banner, "native_gd_banner");
   procedure Tick_C (N : Integer);
                            pragma Import (C, Tick_C, "native_gd_tick");
   procedure Row_C (S : System.Address);
                            pragma Import (C, Row_C, "native_gd_row");

   Backlight : constant ESP32S3.GPIO.Pin_Id := 6;

   Dev : LCD.Device;
   S   : LCD.Session;

   --  Display layout (240x240): title at the top, then four value rows in a
   --  scale-2 font (cell 12x16 px), each padded to Field_Width so the opaque
   --  redraw clears the prior value.
   Field_Width : constant := 19;
   Y_Time      : constant := 56;
   Y_Lat       : constant := 84;
   Y_Lon       : constant := 112;
   Y_Fix       : constant := 140;
   Y_State     : constant := 172;

   Digit : constant String := "0123456789";

   --  Right-justified, zero-padded Width-digit rendering of Value (mod 10**W).
   function Nat_Fixed (Value, Width : Natural) return String is
      R : String (1 .. Width);
      V : Natural := Value;
   begin
      for I in reverse 1 .. Width loop
         R (I) := Digit (V mod 10 + 1);
         V := V / 10;
      end loop;
      return R;
   end Nat_Fixed;

   --  Pad / clip Str to exactly W characters (so opaque cells clear old text).
   function Pad (Str : String; W : Natural) return String is
   begin
      if Str'Length >= W then
         return Str (Str'First .. Str'First + W - 1);
      else
         return Str & (1 .. W - Str'Length => ' ');
      end if;
   end Pad;

   function Fmt_Time (T : GPS.UTC_Time) return String is
     ("UTC " & Nat_Fixed (T.Hour, 2) & ":" & Nat_Fixed (T.Minute, 2)
      & ":" & Nat_Fixed (T.Second, 2));

   --  1e-7-degree integer -> "DD.DDDDDDD H" (Int_W integer digits + hemisphere).
   function Fmt_Deg
     (V : Interfaces.Integer_32; Int_W : Positive; Pos, Neg : Character)
      return String
   is
      A  : constant Natural   := Natural (abs V);
      Ip : constant Natural   := A / 10_000_000;
      Fp : constant Natural   := A mod 10_000_000;
      H  : constant Character := (if V < 0 then Neg else Pos);
   begin
      return Nat_Fixed (Ip, Int_W) & "." & Nat_Fixed (Fp, 7) & ' ' & H;
   end Fmt_Deg;

   function Mode_Str (M : GPS.Fix_Type) return String is
     (case M is when GPS.Fix_None => "--",
                when GPS.Fix_2D   => "2D",
                when GPS.Fix_3D   => "3D");

   --  Mirror one row to the console (NUL-terminate for the C %s glue).
   procedure Console (Line : String) is
      Buf : aliased String (1 .. Line'Length + 1);
   begin
      Buf (1 .. Line'Length) := Line;
      Buf (Buf'Last) := Character'Val (0);
      delay until Clock + Milliseconds (25);   --  space out the 64-byte FIFO
      Row_C (Buf'Address);
   end Console;

   --  Paint one fixed-width row to the panel and echo it to the console.
   procedure Draw_Row (Y : Natural; Text : String; FG : LCD.Color) is
      P : constant String := Pad (Text, Field_Width);
   begin
      LCD.Text.Draw_Text (S, X => 6, Y => Y, Str => P,
                          FG => FG, BG => LCD.Black, Scale => 2);
      Console (P);
   end Draw_Row;

   Amber : constant LCD.Color := LCD.RGB (255, 190, 0);
   Cyan  : constant LCD.Color := LCD.RGB (0, 220, 255);

   N : Natural := 0;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  Backlight first (example's job, not the driver's), then bring up the panel.
   ESP32S3.GPIO.Configure (Backlight, Mode => ESP32S3.GPIO.Output);
   ESP32S3.GPIO.Set (Backlight);

   LCD.Setup (Dev, Sclk => 12, Mosi => 13, DC => 16, CS => 10);   --  240x240
   LCD.Acquire (S, Dev);
   LCD.Init (S);
   LCD.Fill (S, LCD.Black);
   LCD.Text.Draw_Text (S, X => 8, Y => 8, Str => "GPS",
                       FG => LCD.RGB (0, 255, 0), BG => LCD.Black, Scale => 3);

   --  Bring up the GPS service (releases its reader task).
   GPS.Setup (Port => ESP32S3.UART.UART0, Rx => 44, Tx => 43, Baud => 9_600);

   --  Update once a second, forever, as fixes arrive.
   loop
      N := N + 1;
      Tick_C (N);
      declare
         T  : constant GPS.Time_Reading     := GPS.Current_Time;
         P  : constant GPS.Position_Reading := GPS.Current_Position;
         F  : constant GPS.Fix_Reading      := GPS.Current_Fix;
         Sg : constant GPS.Signal_Reading   := GPS.Current_Signal;
         Time_Fresh : constant Boolean :=
           T.Valid and then To_Duration (GPS.Age (T.Updated_At)) < 5.0;
         Pos_Fresh  : constant Boolean :=
           P.Valid and then To_Duration (GPS.Age (P.Updated_At)) < 3.0;
      begin
         if Time_Fresh then
            Draw_Row (Y_Time, Fmt_Time (T.Value), LCD.White);
         else
            Draw_Row (Y_Time, "UTC --:--:--", LCD.White);
         end if;

         if Pos_Fresh then
            Draw_Row (Y_Lat, "Lat " & Fmt_Deg (P.Value.Latitude, 2, 'N', 'S'),
                      LCD.White);
            Draw_Row (Y_Lon, "Lon " & Fmt_Deg (P.Value.Longitude, 3, 'E', 'W'),
                      LCD.White);
         else
            Draw_Row (Y_Lat, "Lat --", LCD.White);
            Draw_Row (Y_Lon, "Lon --", LCD.White);
         end if;

         --  Mode (2D/3D) from GSA; satellites USED in the solution from GGA
         --  (stable, unlike the per-constellation GSV in-view count).
         Draw_Row (Y_Fix, "Fix " & Mode_Str (Sg.Mode)
                          & " Sat " & Nat_Fixed (F.Satellites, 2), Cyan);

         if Pos_Fresh then
            Draw_Row (Y_State, "* fix live", LCD.RGB (0, 255, 0));
         else
            Draw_Row (Y_State, "* searching", Amber);
         end if;
      end;

      delay until Clock + Seconds (1);
   end loop;
end Main;
