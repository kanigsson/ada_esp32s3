--  Multi-sensor dashboard on a 240x240 ST7789 panel (bare-metal ESP32-S3, no
--  FreeRTOS, no IDF)
--  ====================================================================
--
--  What it demonstrates
--  --------------------
--  Four reusable HAL drivers feeding four views that cycle on screen, five
--  seconds each:
--
--    GPS  ESP32S3.GPS        UART0 (GPS TXD->U0RXD=IO44, U0TXD->GPS RXD=IO43,
--                            9600) -- live UTC / latitude / longitude / fix.
--    ENV  ESP32S3.SHT41      I2C0 0x44 -- temperature + relative humidity.
--    RTC  ESP32S3.PCF85063A  I2C0 0x51 -- calendar date / time / weekday.
--    IMU  ESP32S3.QMI8658C   I2C0 0x6B/0x6A -- 3-axis accel (g) + die temp.
--
--  All three I2C parts share one bus (SDA=IO8 SCL=IO7); each driver opens a
--  short-lived I2C Session per read, so they coexist.  The GPS is a background
--  task publishing into a protected store.  The display (SPI2: SCLK=IO12
--  MOSI=IO13 DC=IO16 CS=IO10; backlight IO6 driven HERE) is held in ONE Session
--  for the whole run -- so no task can corrupt the controller -- while each text
--  update locks the SPI host only for its own transfers.
--
--  Build & run
--  -----------
--  `./x run esp32s3_gps_display` -- needs the embedded runtime profile, which
--  the example's build.sh selects (ESP32S3_RTS_PROFILE=embedded), because all
--  four drivers use controlled Sessions / a background task.
--
--  Output
--  ------
--  The panel is the real output; the console mirrors every row pushed to it, so
--  a live run can be checked over serial too (the panel itself is write-only).
--  After a ~2.5 s Ada-mascot splash the views cycle forever.  Each view prints a
--  "== <title> : <subtitle> ==" header on entry, then a value row per line once a
--  second; e.g. the GPS view shows "UTC ..", "Lat ..", "Lon ..", "Fix .. Sat .."
--  once locked, or "* searching" with "--" placeholders until it gets sky view.
--
--  Hardware / wiring
--  -----------------
--    LCD  ST7789 240x240 panel on SPI2: SCLK=IO12 MOSI=IO13 DC=IO16 CS=IO10;
--         backlight IO6 (driven here, not by the driver); RST not wired (uses
--         the controller's software reset).  Panel is write-only.
--    GPS  NMEA receiver on UART0: GPS TXD->U0RXD=IO44, U0TXD->GPS RXD=IO43, 9600.
--    I2C  SHT41 / PCF85063A / QMI8658C share I2C0: SDA=IO8 SCL=IO7.
with Interfaces;    use type Interfaces.Integer_32;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.UART;
with ESP32S3.GPS;
with ESP32S3.SHT41;
with ESP32S3.PCF85063A;
with ESP32S3.QMI8658C;
with ESP32S3.ST7789;
with ESP32S3.ST7789.Text;
with ESP32S3.Log;    use ESP32S3.Log;
with Ada_Logo;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package GPS renames ESP32S3.GPS;
   package SHT renames ESP32S3.SHT41;
   package RTC renames ESP32S3.PCF85063A;
   package IMU renames ESP32S3.QMI8658C;
   package LCD renames ESP32S3.ST7789;
   use type GPS.Fix_Type;
   use type SHT.Status;
   use type RTC.Status;
   use type IMU.Status;

   procedure Banner is
   begin
      Put_Line ("[dash] multi-sensor dashboard -> ST7789 240x240");
      Put_Line ("[dash]   GPS  UART0 rx=44 tx=43 9600   (NMEA)");
      Put_Line ("[dash]   I2C0 sda=8 scl=7  SHT41 0x44 / RTC 0x51 / IMU 0x6b");
      Put_Line ("[dash]   LCD  SPI2  sclk=12 mosi=13 dc=16 cs=10 bl=6");
      Put_Line ("[dash]   cycling GPS / ENV / RTC / IMU, 5 s each");
   end Banner;

   --  Pin assignments (see the wiring table in the header).
   Backlight : constant ESP32S3.GPIO.Pin_Id := 6;    --  LCD backlight enable.
   Sda       : constant ESP32S3.GPIO.Pin_Id := 8;    --  shared I2C0 data.
   Scl       : constant ESP32S3.GPIO.Pin_Id := 7;    --  shared I2C0 clock.

   --  Display geometry (ST7789, portrait).
   Panel_W : constant := 240;    --  panel width  in pixels.
   Panel_H : constant := 240;    --  panel height in pixels.

   --  SPI2 pins for the panel.
   LCD_Sclk : constant := 12;
   LCD_Mosi : constant := 13;
   LCD_DC   : constant := 16;    --  data/command select.
   LCD_CS   : constant := 10;    --  chip select.

   --  UART0 pins / baud for the NMEA GPS receiver.
   GPS_Rx_Pin  : constant := 44;      --  U0RXD <- GPS TXD.
   GPS_Tx_Pin  : constant := 43;      --  U0TXD -> GPS RXD (unused here).
   GPS_Baud    : constant := 9_600;   --  standard NMEA bit rate.

   --  I2C addresses are named by the drivers; the QMI8658C is probed at runtime
   --  (SA0-low 0x6B, falling back to SA0-high 0x6A).

   Disp    : LCD.Device;
   S       : LCD.Session;
   Env     : SHT.Device;
   Clk     : RTC.Device;
   Imu_Dev : IMU.Device;

   --  Set True once the RTC has been loaded from a GPS UTC fix (done once).
   RTC_Synced : Boolean := False;

   --  Display layout (240x240): scale-3 title, scale-1 subtitle, then up to four
   --  value rows in the scale-2 font (cell 12x16), each padded to a fixed width
   --  so the opaque redraw overwrites the previous value.
   Title_Scale : constant := 3;    --  view title font scale (base 5x7 cell).
   Sub_Scale   : constant := 1;    --  subtitle font scale.
   Value_Scale : constant := 2;    --  value-row font scale -> 12x16 cell.

   --  At scale 2 the 240 px width holds 19 padded characters; padding to this
   --  fixed width means every opaque redraw fully covers the previous value.
   Field_Width : constant := 19;

   --  Text origins.  Title/subtitle sit near the top-left; value rows are inset
   --  and spaced one value-cell height (16 px) apart.
   Title_X : constant := 8;
   Title_Y : constant := 8;
   Sub_X   : constant := 8;
   Sub_Y   : constant := 40;
   Row_X   : constant := 6;     --  left inset of every value row.
   R1      : constant := 64;    --  Y of value row 1.
   R2      : constant := 92;    --  Y of value row 2 (R1 + 28).
   R3      : constant := 120;   --  Y of value row 3.
   R4      : constant := 148;   --  Y of value row 4.

   --  View accent colours (RGB565 via LCD.RGB; R, G, B are 0..255).
   White : constant LCD.Color := LCD.White;
   Green : constant LCD.Color := LCD.RGB (0, 255, 0);
   Cyan  : constant LCD.Color := LCD.RGB (0, 220, 255);
   Amber : constant LCD.Color := LCD.RGB (255, 190, 0);
   Dim   : constant LCD.Color := LCD.RGB (130, 130, 130);   --  muted/grey.

   Digit : constant String := "0123456789";

   ----------------------------------------------------------------------------
   --  Formatting helpers (no Text_IO on bare metal -- build strings by hand).
   ----------------------------------------------------------------------------

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

   --  Minimal-width rendering (no leading zeros).
   function Nat_Img (V : Natural) return String is
     (if V < 10 then (1 => Digit (V + 1))
      else Nat_Img (V / 10) & Digit (V mod 10 + 1));

   --  Pad / clip Str to exactly W characters.
   function Pad (Str : String; W : Natural) return String is
     (if Str'Length >= W then Str (Str'First .. Str'First + W - 1)
      else Str & (1 .. W - Str'Length => ' '));

   --  A milli-unit integer (e.g. 23_450) -> "23.45"; Signed prefixes '+' for
   --  non-negative values (handy for accelerometer axes).
   function Fmt_Milli (M : Integer; Signed : Boolean := False) return String is
      A   : constant Natural := abs M;
      Sgn : constant String  :=
        (if M < 0 then "-" elsif Signed then "+" else "");
   begin
      return Sgn & Nat_Img (A / 1000) & "." & Nat_Fixed ((A mod 1000) / 10, 2);
   end Fmt_Milli;

   function Fmt_Time (T : GPS.UTC_Time) return String is
     ("UTC " & Nat_Fixed (T.Hour, 2) & ":" & Nat_Fixed (T.Minute, 2)
      & ":" & Nat_Fixed (T.Second, 2));

   --  1e-7-degree integer -> "DD.DDDDDDD H" (Int_W integer digits + hemisphere).
   function Fmt_Deg
     (V : Interfaces.Integer_32; Int_W : Positive; Pos, Neg : Character)
      return String
   is
      A : constant Natural := Natural (abs V);
   begin
      return Nat_Fixed (A / 10_000_000, Int_W) & "."
             & Nat_Fixed (A mod 10_000_000, 7) & ' '
             & (if V < 0 then Neg else Pos);
   end Fmt_Deg;

   function Mode_Str (M : GPS.Fix_Type) return String is
     (case M is when GPS.Fix_None => "--",
                when GPS.Fix_2D   => "2D",
                when GPS.Fix_3D   => "3D");

   function Day_Str (W : RTC.Weekday) return String is
     (case W is when RTC.Sunday => "Sun", when RTC.Monday    => "Mon",
                when RTC.Tuesday => "Tue", when RTC.Wednesday => "Wed",
                when RTC.Thursday => "Thu", when RTC.Friday   => "Fri",
                when RTC.Saturday => "Sat");

   --  Weekday for a Gregorian date (Sakamoto's algorithm; 0 = Sunday).  The GPS
   --  carries date + time but no weekday, so derive it before loading the RTC.
   function Weekday_Of (Y, M, D : Natural) return RTC.Weekday is
      T  : constant array (1 .. 12) of Natural :=
             (0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4);
      Yr : Natural := Y;
   begin
      if M < 3 then
         Yr := Yr - 1;
      end if;
      return RTC.Weekday'Val
        ((Yr + Yr / 4 - Yr / 100 + Yr / 400 + T (M) + D) mod 7);
   end Weekday_Of;

   ----------------------------------------------------------------------------
   --  Output helpers.
   ----------------------------------------------------------------------------

   --  A reading is "fresh" only if its protected-store snapshot is younger than
   --  this; older than that and the fix is treated as stale (placeholders shown).
   Time_Stale_After : constant Duration := 5.0;   --  seconds, for UTC time.
   Pos_Stale_After  : constant Duration := 3.0;   --  seconds, for lat/lon fix.

   --  Mirror one line to the console.  The UART TX FIFO is 64 bytes; pace console
   --  writes so a burst of rows does not overrun it (each row is one line).
   Console_Pace : constant := 25;   --  milliseconds between mirrored lines.

   procedure Console (Line : String) is
   begin
      delay until Clock + Milliseconds (Console_Pace);
      Put ("[dash] ");
      Put_Line (Line);
   end Console;

   --  Paint one fixed-width row to the panel (over the view's black background)
   --  and echo it to the console.
   procedure Draw_Row (Y : Natural; Text : String; FG : LCD.Color) is
      P : constant String := Pad (Text, Field_Width);
   begin
      LCD.Text.Draw_Text (S, X => Row_X, Y => Y, Str => P,
                          FG => FG, BG => LCD.Black, Scale => Value_Scale);
      Console (P);
   end Draw_Row;

   --  Clear the panel and draw a view's title + subtitle (once per view entry).
   procedure Header (Title, Sub : String; C : LCD.Color) is
   begin
      LCD.Fill (S, LCD.Black);
      LCD.Text.Draw_Text (S, X => Title_X, Y => Title_Y, Str => Title,
                          FG => C, BG => LCD.Black, Scale => Title_Scale);
      LCD.Text.Draw_Text (S, X => Sub_X, Y => Sub_Y, Str => Sub,
                          FG => Dim, BG => LCD.Black, Scale => Sub_Scale);
      Console ("== " & Title & " : " & Sub & " ==");
   end Header;

   ----------------------------------------------------------------------------
   --  Per-view value updates (called once a second while the view is showing).
   ----------------------------------------------------------------------------

   procedure Update_GPS is
      T : constant GPS.Time_Reading     := GPS.Current_Time;
      P : constant GPS.Position_Reading := GPS.Current_Position;
      F : constant GPS.Fix_Reading      := GPS.Current_Fix;
      G : constant GPS.Signal_Reading   := GPS.Current_Signal;
      Time_Fresh : constant Boolean :=
        T.Valid and then To_Duration (GPS.Age (T.Updated_At)) < Time_Stale_After;
      Pos_Fresh : constant Boolean :=
        P.Valid and then To_Duration (GPS.Age (P.Updated_At)) < Pos_Stale_After;
   begin
      if Time_Fresh then
         Draw_Row (R1, Fmt_Time (T.Value), White);
      else
         Draw_Row (R1, "UTC --:--:--", White);
      end if;
      if Pos_Fresh then
         Draw_Row (R2, "Lat " & Fmt_Deg (P.Value.Latitude, 2, 'N', 'S'), White);
         Draw_Row (R3, "Lon " & Fmt_Deg (P.Value.Longitude, 3, 'E', 'W'), White);
         Draw_Row (R4, "Fix " & Mode_Str (G.Mode) & " Sat "
                       & Nat_Fixed (F.Satellites, 2), Green);
      else
         Draw_Row (R2, "Lat --", White);
         Draw_Row (R3, "Lon --", White);
         Draw_Row (R4, "* searching", Amber);
      end if;
   end Update_GPS;

   procedure Update_Env is
      M  : SHT.Measurement;
      St : SHT.Status;
   begin
      SHT.Measure (Env, M, St);
      if St = SHT.OK then
         Draw_Row (R1, "Temp " & Fmt_Milli (M.Temperature) & " C", White);
         Draw_Row (R2, "Hum  " & Fmt_Milli (M.Humidity) & " %", Cyan);
      else
         Draw_Row (R1, "Temp  --", Amber);
         Draw_Row (R2, "Hum   --", Amber);
      end if;
   end Update_Env;

   procedure Update_RTC is
      T     : RTC.Time;
      Valid : Boolean;
      St    : RTC.Status;
   begin
      RTC.Get_Time (Clk, T, Valid, St);
      if St = RTC.OK then
         Draw_Row (R1, "Date " & Nat_Fixed (T.Year, 4) & "-"
                       & Nat_Fixed (T.Month, 2) & "-" & Nat_Fixed (T.Day, 2),
                   White);
         Draw_Row (R2, "Time " & Nat_Fixed (T.Hour, 2) & ":"
                       & Nat_Fixed (T.Minute, 2) & ":" & Nat_Fixed (T.Second, 2),
                   White);
         Draw_Row (R3, "Day  " & Day_Str (T.Day_Of_Week)
                       & (if Valid then "" else " (unset)"), Cyan);
         if RTC_Synced then
            Draw_Row (R4, "Src  GPS UTC", Green);
         elsif Valid then
            Draw_Row (R4, "Src  battery", Dim);
         else
            Draw_Row (R4, "Src  awaiting GPS", Amber);
         end if;
      else
         Draw_Row (R1, "RTC bus error", Amber);
      end if;
   end Update_RTC;

   --  QMI8658C die-temperature scale: the raw 16-bit reading is in 1/256 C.
   IMU_Temp_LSB_Per_C : constant := 256;

   procedure Update_IMU is
      A   : IMU.Axes;
      Raw : Interfaces.Integer_16;
      St  : IMU.Status;
      St2 : IMU.Status;

      --  Accelerometer counts per 1 g for the configured range (set in Configure
      --  below); raw counts * 1000 / LSB gives milli-g for Fmt_Milli.
      LSB : constant Positive := IMU.Accel_LSB_Per_G (Imu_Dev);
   begin
      IMU.Read_Accelerometer (Imu_Dev, A, St);
      IMU.Read_Temperature (Imu_Dev, Raw, St2);
      if St = IMU.OK then
         Draw_Row (R1, "Ax " & Fmt_Milli (Integer (A.X) * 1000 / LSB, True)
                       & " g", White);
         Draw_Row (R2, "Ay " & Fmt_Milli (Integer (A.Y) * 1000 / LSB, True)
                       & " g", White);
         Draw_Row (R3, "Az " & Fmt_Milli (Integer (A.Z) * 1000 / LSB, True)
                       & " g", White);
      else
         Draw_Row (R1, "IMU bus error", Amber);
      end if;
      if St2 = IMU.OK then
         Draw_Row (R4, "Temp "
                       & Fmt_Milli (Integer (Raw) * 1000 / IMU_Temp_LSB_Per_C)
                       & " C", Cyan);
      end if;
   end Update_IMU;

   --  Once the GPS has a position fix with a valid date + time, load that UTC
   --  into the PCF85063A -- one time.  Set_Time clears the oscillator-stop flag,
   --  so the RTC then reads back Valid until power is lost.  The GPS UTC snapshot
   --  can be up to ~1 s old (no PPS alignment here), which is fine for a clock.
   procedure Sync_RTC_From_GPS is
      P  : constant GPS.Position_Reading := GPS.Current_Position;
      Dt : constant GPS.Date_Reading     := GPS.Current_Date;
      Tm : constant GPS.Time_Reading     := GPS.Current_Time;
      Locked : constant Boolean :=
        P.Valid and then To_Duration (GPS.Age (P.Updated_At)) < Pos_Stale_After;
      T  : RTC.Time;
      St : RTC.Status;
   begin
      if RTC_Synced or else not (Locked and then Dt.Valid and then Tm.Valid) then
         return;
      end if;
      T := (Year        => Dt.Value.Year,
            Month       => Dt.Value.Month,
            Day         => Dt.Value.Day,
            Day_Of_Week => Weekday_Of (Dt.Value.Year, Dt.Value.Month,
                                       Dt.Value.Day),
            Hour        => Tm.Value.Hour,
            Minute      => Tm.Value.Minute,
            Second      => Tm.Value.Second);
      RTC.Set_Time (Clk, T, St);
      if St = RTC.OK then
         RTC_Synced := True;
         Console ("RTC set from GPS UTC "
                  & Nat_Fixed (T.Year, 4) & "-" & Nat_Fixed (T.Month, 2) & "-"
                  & Nat_Fixed (T.Day, 2) & " " & Nat_Fixed (T.Hour, 2) & ":"
                  & Nat_Fixed (T.Minute, 2) & ":" & Nat_Fixed (T.Second, 2));
      end if;
   end Sync_RTC_From_GPS;

   type View_Kind is (V_GPS, V_Env, V_RTC, V_IMU);
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  Backlight first (example's job, not the driver's), then bring up the panel.
   ESP32S3.GPIO.Configure (Backlight, Mode => ESP32S3.GPIO.Output);
   ESP32S3.GPIO.Set (Backlight);

   LCD.Setup (Disp, Sclk => LCD_Sclk, Mosi => LCD_Mosi,
              DC => LCD_DC, CS => LCD_CS);                          --  240x240
   LCD.Acquire (S, Disp);
   LCD.Init (S);

   --  Startup splash: the textless Ada mascot, full screen for ~2.5 s.
   LCD.Draw_Bitmap (S, X => 0, Y => 0,
                    W => Ada_Logo.Width, H => Ada_Logo.Height,
                    Pixels => Ada_Logo.Pixels);
   Console ("splash: Ada logo");
   delay until Clock + Milliseconds (2500);   --  ~2.5 s splash hold.
   LCD.Fill (S, LCD.Black);

   --  Bring up the GPS service (releases its reader task) and the I2C sensors.
   GPS.Setup (Port => ESP32S3.UART.UART0,
              Rx => GPS_Rx_Pin, Tx => GPS_Tx_Pin, Baud => GPS_Baud);
   SHT.Setup (Env, Sda => Sda, Scl => Scl);
   RTC.Setup (Clk, Sda => Sda, Scl => Scl);

   --  IMU: probe the SA0-low address (0x6B); fall back to 0x6A, then configure.
   declare
      Id : Interfaces.Unsigned_8;
      St : IMU.Status;
      use type Interfaces.Unsigned_8;
   begin
      IMU.Setup (Imu_Dev, Sda => Sda, Scl => Scl,
                 Address => IMU.Address_SA0_Low);
      IMU.Read_Who_Am_I (Imu_Dev, Id, St);
      if St /= IMU.OK or else Id /= IMU.Who_Am_I_Value then
         IMU.Setup (Imu_Dev, Sda => Sda, Scl => Scl,
                    Address => IMU.Address_SA0_High);
      end if;
      IMU.Reset (Imu_Dev, St);
      delay until Clock + Milliseconds (20);
      IMU.Configure (Imu_Dev, Accel => IMU.Range_8G, Gyro => IMU.Range_512DPS,
                     Rate => IMU.ODR_235_Hz, Result => St);
   end;

   --  Cycle the views, five seconds (five 1 Hz updates) on each.
   loop
      for V in View_Kind loop
         case V is
            when V_GPS => Header ("GPS", "NMEA receiver",    Green);
            when V_Env => Header ("ENV", "SHT41 temp/humid", Cyan);
            when V_RTC => Header ("RTC", "PCF85063A clock",  White);
            when V_IMU => Header ("IMU", "QMI8658C 6-axis",  Amber);
         end case;

         for Sec in 1 .. 5 loop
            Sync_RTC_From_GPS;   --  one-time, as soon as the GPS locks
            case V is
               when V_GPS => Update_GPS;
               when V_Env => Update_Env;
               when V_RTC => Update_RTC;
               when V_IMU => Update_IMU;
            end case;
            delay until Clock + Seconds (1);
         end loop;
      end loop;
   end loop;
end Main;
