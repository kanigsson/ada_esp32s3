--  NMEA GPS receiver driver demo on the bare-metal ESP32-S3 (no FreeRTOS, no
--  IDF).  Exercises the reusable HAL GPS driver (ESP32S3.GPS), a task-driven
--  UART service, in two phases:
--
--    self-test  Inject canned GGA/RMC sentences (and one with a bad checksum)
--               BEFORE Setup -- so the reader task is still suspended and the
--               protected store is quiescent -- and check that decoding,
--               storage, and the paired Position record are correct.  This
--               proves the decoder on silicon with no live receiver.
--
--    live       Setup UART0 (GPS TXD -> U0RXD = GPIO44; our U0TXD -> GPS RXD =
--               GPIO43; 9600 baud), releasing the reader task, then once a
--               second print the latest fix + its age.  With no antenna lock the
--               position stays invalid/stale while sentences still arrive (the
--               fix group's rx_age advancing shows reception is live).
--
--  Report goes through the ROM printf glue; the Ada driver does all the UART +
--  NMEA work.
with System;
with Interfaces;   use type Interfaces.Integer_32;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.UART;
with ESP32S3.GPS;
with ESP32S3.GPS.L76K;   --  L76K-specific PCAS commands

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package GPS  renames ESP32S3.GPS;
   package L76K renames ESP32S3.GPS.L76K;
   use type GPS.Fix_Quality;

   --  PCAS04 mode number (1 .. 7) for a constellation selection.
   function Config_Mode (C : L76K.Constellation) return int is
     (int (L76K.Constellation'Pos (C)) + 1);

   procedure Banner;   pragma Import (C, Banner,   "native_gps_banner");
   procedure Live_Hdr; pragma Import (C, Live_Hdr, "native_gps_live_hdr");
   procedure Check (Code, Ok : int);
                       pragma Import (C, Check,    "native_gps_check");
   procedure Live (Time_Valid, HH, MM, SS, Pos_Fresh,
                   Lat_E7, Lon_E7, In_View, Max_SNR, Fix_Type : int);
                       pragma Import (C, Live,     "native_gps_live");
   procedure Raw (S : System.Address; N : int);
                       pragma Import (C, Raw,      "native_gps_raw");
   procedure Sat_Hdr (Count : int);
                       pragma Import (C, Sat_Hdr,  "native_gps_sat_hdr");
   procedure Sat (Sys, PRN, El, Az, SNR : int);
                       pragma Import (C, Sat,      "native_gps_sat");
   procedure Cfg (Mode : int);
                       pragma Import (C, Cfg,      "native_gps_cfg");
   procedure Done;     pragma Import (C, Done,     "native_gps_done");

   --  Canonical NMEA examples (checksums verified): 48 07.038' N, 011 31.000' E.
   GGA : constant String :=
     "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47";
   RMC : constant String :=
     "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A";
   ZDA : constant String :=   --  UTC 19:27:39, 22/06/2026 (time + date, no fix)
     "$GNZDA,192739.000,22,06,2026,00,00*4F";
   GLL : constant String :=   --  51 30.000' N, 000 07.500' W
     "$GPGLL,5130.000,N,00007.500,W,123519,A,A*5D";
   VTG : constant String :=   --  course 123.4 true, 54.7 kn
     "$GPVTG,123.4,T,,M,054.7,N,101.3,K,A*0C";
   GSV : constant String :=   --  11 in view, strongest C/N0 = 35
     "$GPGSV,3,1,11,04,40,083,30,05,28,290,25,09,15,180,20,12,60,000,35*75";
   GSA : constant String :=   --  3D fix, 5 used, HDOP 1.30
     "$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.50,1.30,2.10*09";
   Bad : constant String :=   --  same GGA, deliberately wrong checksum
     "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00";

   Ok : Boolean;

   --  Space the back-to-back self-test lines so the 64-byte console FIFO drains.
   procedure Report (Code : int; Pass : Boolean) is
   begin
      delay until Clock + Milliseconds (40);
      Check (Code, Boolean'Pos (Pass));
   end Report;

begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Banner;

   --------------------------------------------------------------------------
   --  Self-test (reader task still suspended -> deterministic store).
   --------------------------------------------------------------------------
   GPS.Inject (GGA, Ok);
   Report (0, Ok);
   declare
      P : constant GPS.Position_Reading := GPS.Current_Position;
      F : constant GPS.Fix_Reading      := GPS.Current_Fix;
      T : constant GPS.Time_Reading     := GPS.Current_Time;
   begin
      Report (1, P.Valid
                 and then P.Value.Latitude = 481_173_000
                 and then P.Value.Longitude = 115_166_666);
      Report (2, F.Quality = GPS.GPS_Fix
                 and then F.Satellites = 8
                 and then F.Altitude_MM = 545_400);
      Report (3, T.Valid
                 and then T.Value.Hour = 12
                 and then T.Value.Minute = 35
                 and then T.Value.Second = 19);
   end;

   GPS.Inject (RMC, Ok);
   Report (4, Ok);
   declare
      D : constant GPS.Date_Reading     := GPS.Current_Date;
      V : constant GPS.Velocity_Reading := GPS.Current_Velocity;
   begin
      Report (5, D.Valid
                 and then D.Value.Day = 23
                 and then D.Value.Month = 3
                 and then D.Value.Year = 2094);
      Report (6, V.Valid
                 and then V.Speed_MMS = 11_523
                 and then V.Course_CDeg = 8_440);
   end;

   --  ZDA: UTC time + date, NOT gated on a fix (updates the clock before lock).
   GPS.Inject (ZDA, Ok);
   declare
      T : constant GPS.Time_Reading := GPS.Current_Time;
      D : constant GPS.Date_Reading := GPS.Current_Date;
   begin
      Report (8, Ok
                 and then T.Valid and then T.Value.Hour = 19
                 and then T.Value.Minute = 27 and then T.Value.Second = 39
                 and then D.Valid and then D.Value.Day = 22
                 and then D.Value.Month = 6 and then D.Value.Year = 2026);
   end;

   --  GLL: position (distinct coordinate, so this proves GLL field decoding).
   GPS.Inject (GLL, Ok);
   declare
      P : constant GPS.Position_Reading := GPS.Current_Position;
   begin
      Report (9, Ok and then P.Valid
                 and then P.Value.Latitude = 515_000_000
                 and then P.Value.Longitude = -1_250_000);
   end;

   --  VTG: velocity (distinct from RMC's, so this proves VTG field decoding).
   GPS.Inject (VTG, Ok);
   declare
      V : constant GPS.Velocity_Reading := GPS.Current_Velocity;
   begin
      Report (10, Ok and then V.Valid
                  and then V.Speed_MMS = 28_140 and then V.Course_CDeg = 12_340);
   end;

   --  GSV: satellites in view + strongest C/N0 (acquisition, no fix needed).
   GPS.Inject (GSV, Ok);
   declare
      S : constant GPS.Signal_Reading := GPS.Current_Signal;
   begin
      Report (11, Ok and then S.Valid
                  and then S.In_View = 11 and then S.Max_SNR = 35);
   end;

   --  GSV satellite list: the 4 satellites in that message, decoded into entries.
   declare
      L : GPS.Satellite_List (1 .. GPS.Max_Satellites);
      N : Natural;
      use type GPS.GNSS_System;
   begin
      GPS.Satellites_In_View (L, N);
      Report (13, N = 4
                  and then L (1).System = GPS.GPS
                  and then L (1).PRN = 4 and then L (1).SNR = 30
                  and then L (4).PRN = 12 and then L (4).SNR = 35);
   end;

   --  GSA: solution mode (3D) + dilution of precision.
   GPS.Inject (GSA, Ok);
   declare
      S : constant GPS.Signal_Reading := GPS.Current_Signal;
      use type GPS.Fix_Type;
   begin
      Report (12, Ok and then S.Valid
                  and then S.Mode = GPS.Fix_3D
                  and then S.Used = 5 and then S.HDOP_C = 130);
   end;

   GPS.Inject (Bad, Ok);
   Report (7, not Ok);            --  a bad checksum must be rejected

   --------------------------------------------------------------------------
   --  Live: bring up UART0 on the GPS pins and release the reader task.
   --------------------------------------------------------------------------
   delay until Clock + Milliseconds (40);
   Live_Hdr;
   GPS.Setup (Port => ESP32S3.UART.UART0, Rx => 44, Tx => 43, Baud => 9_600);

   for Tick in 1 .. 70 loop
      delay until Clock + Seconds (1);
      declare
         P : constant GPS.Position_Reading := GPS.Current_Position;
         T : constant GPS.Time_Reading     := GPS.Current_Time;
         S : constant GPS.Signal_Reading   := GPS.Current_Signal;
         Sats : GPS.Satellite_List (1 .. GPS.Max_Satellites);
         NSat : Natural;
         Pos_Fresh : constant Boolean :=    --  a live fix updates ~1 Hz
           P.Valid and then To_Duration (GPS.Age (P.Updated_At)) < 3.0;
         Time_Fresh : constant Boolean :=    --  live UTC (ZDA arrives before lock)
           T.Valid and then To_Duration (GPS.Age (T.Updated_At)) < 5.0;
      begin
         GPS.Satellites_In_View (Sats, NSat);   --  table count (all systems)
         Live (Time_Valid => Boolean'Pos (Time_Fresh),
               HH         => int (T.Value.Hour),
               MM         => int (T.Value.Minute),
               SS         => int (T.Value.Second),
               Pos_Fresh  => Boolean'Pos (Pos_Fresh),
               Lat_E7     => int (P.Value.Latitude),
               Lon_E7     => int (P.Value.Longitude),
               In_View    => int (NSat),
               Max_SNR    => int (S.Max_SNR),
               Fix_Type   => GPS.Fix_Type'Pos (S.Mode));

         --  Echo the actual raw sentence (spaced so the FIFO drains; long
         --  sentences are split into two lines to stay under the console FIFO).
         delay until Clock + Milliseconds (40);
         declare
            Buf  : String (1 .. 90);
            Len  : Natural;
            Half : constant := 45;
         begin
            GPS.Last_Sentence (Buf, Len);
            Raw (Buf'Address, int (Natural'Min (Len, Half)));
            if Len > Half then
               delay until Clock + Milliseconds (40);
               Raw (Buf (Buf'First + Half)'Address, int (Len - Half));
            end if;
         end;

         --  Every 10 s, dump the full satellite-in-view list, one per line.
         if Tick mod 10 = 0 then
            delay until Clock + Milliseconds (40);
            Sat_Hdr (int (NSat));
            for I in 1 .. NSat loop
               delay until Clock + Milliseconds (40);
               Sat (Sys => GPS.GNSS_System'Pos (Sats (I).System),
                    PRN => int (Sats (I).PRN),
                    El  => int (Sats (I).Elevation),
                    Az  => int (Sats (I).Azimuth),
                    SNR => int (Sats (I).SNR));
            end loop;
         end if;

         --  L76K PCAS04 test: at tick 5 (after the default GPS+BeiDou baseline)
         --  enable ALL constellations.  Disabling a constellation is instant,
         --  but ENABLING GLONASS means acquiring those satellites from scratch,
         --  so GLONASS (GL) appears in the dumps a while later.
         if Tick = 5 then
            delay until Clock + Milliseconds (40);
            Cfg (Config_Mode (L76K.GPS_BeiDou_GLONASS));
            L76K.Set_Constellation (L76K.GPS_BeiDou_GLONASS);
         end if;
      end;
   end loop;

   delay until Clock + Milliseconds (40);
   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
