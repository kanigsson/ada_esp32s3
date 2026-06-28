with Interfaces; use type Interfaces.Unsigned_8;

package body ESP32S3.GPS.NMEA with SPARK_Mode => On is

   subtype LLI is Long_Long_Integer;

   --  Accumulator cap shared by the integer/fraction readers: a parsed value can
   --  never exceed 1e9, so every later widening into LLI (Coord / Scaled) and the
   --  one Natural add (To_Date's 2000 + yy) stays provably in range.  Realistic
   --  NMEA fields are tiny, so the cap is never reached in practice -- it only
   --  fences off a hostile, arbitrarily long digit run.
   Nat_Cap   : constant := 1_000_000_000;   --  reader results are < this
   Digit_Cap : constant := 99_999_999;      --  stop one decimal short of Nat_Cap

   ---------------------------------------------------------------------------
   --  Small string helpers (no secondary stack: all return scalars or work on
   --  slices of the caller's Sentence).
   ---------------------------------------------------------------------------

   --  Hex value of one ASCII nibble, or -1 if not a hex digit.
   function Hex_Val (C : Character) return Integer is
     (case C is
         when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
         when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
         when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
         when others     => -1);

   --  10**P as an LLI, for P in 0 .. 9.  A total case (not the "**" operator) so
   --  the prover sees the exact value and bounds the Scaled multiply directly.
   function Pow10 (P : Natural) return LLI is
     (case P is
         when 0      => 1,
         when 1      => 10,
         when 2      => 100,
         when 3      => 1_000,
         when 4      => 10_000,
         when 5      => 100_000,
         when 6      => 1_000_000,
         when 7      => 10_000_000,
         when 8      => 100_000_000,
         when others => 1_000_000_000)
   with Pre  => P <= 9,
        Post => Pow10'Result >= 1 and then Pow10'Result <= Nat_Cap;

   --  Unsigned integer value of the leading digits of S (stops at the first
   --  non-digit); empty / no digits -> 0.  Capped at < Nat_Cap so a long digit
   --  run can neither overflow here nor downstream.
   function To_Nat (S : String) return Natural with
     Post => To_Nat'Result <= Nat_Cap
   is
      Acc : Natural := 0;
   begin
      for C of S loop
         pragma Loop_Invariant (Acc <= 10 * Digit_Cap + 9);
         exit when C not in '0' .. '9';
         exit when Acc > Digit_Cap;
         Acc := Acc * 10 + (Character'Pos (C) - Character'Pos ('0'));
      end loop;
      return Acc;
   end To_Nat;

   --  Fractional digits of S scaled to exactly Places digits (pad or truncate).
   --  e.g. Frac ("123", 5) = 12300 ;  Frac ("123456", 5) = 12345.
   function Frac (S : String; Places : Natural) return Natural with
     Pre  => Places <= 9,
     Post => Frac'Result <= Nat_Cap
   is
      Acc : Natural := 0;
      N   : Natural := 0;
   begin
      for C of S loop
         pragma Loop_Invariant (N <= Places);
         pragma Loop_Invariant (Acc <= 10 * Digit_Cap + 9);
         exit when C not in '0' .. '9' or else N = Places;
         exit when Acc > Digit_Cap;
         Acc := Acc * 10 + (Character'Pos (C) - Character'Pos ('0'));
         N := N + 1;
      end loop;
      while N < Places loop
         pragma Loop_Invariant (Acc <= 10 * Digit_Cap + 9);
         pragma Loop_Variant (Decreases => Places - N);
         exit when Acc > Digit_Cap;
         Acc := Acc * 10;
         N := N + 1;
      end loop;
      return Acc;
   end Frac;

   --  Return field number N (0-based) of a comma-separated payload, as a slice
   --  of S.  Out-of-range -> an empty slice.  The result lies within S'Range.
   --  The result is a slice of S, so its 'Last inherits S's "realistic window"
   --  cap -- which is all the field consumers (Coord / To_Time / Scaled) need to
   --  rule out index overflow.  (A within-S'Range 'First bound is unprovable for a
   --  pathological empty S, whose 'First/'Last SPARK models independently, and no
   --  consumer relies on it.)
   function Field (S : String; N : Natural) return String with
     Pre  => S'Last <= Integer'Last - 1,
     Post => Field'Result'Last <= Integer'Last - 1
   is
      Start : Integer := S'First;
      Count : Natural := 0;
   begin
      for I in S'Range loop
         pragma Loop_Invariant
           (Start >= S'First and then Start <= I
            and then Count <= I - S'First);
         if S (I) = ',' then
            if Count = N then
               return S (Start .. I - 1);
            end if;
            Count := Count + 1;
            Start := I + 1;
         end if;
      end loop;
      if Count = N then
         return S (Start .. S'Last);
      end if;
      return S (S'Last + 1 .. S'Last);   --  empty, and provably within S'Range
   end Field;

   ---------------------------------------------------------------------------
   --  Decimal "iii.fff" -> integer scaled by 10**Places (e.g. metres -> mm with
   --  Places = 3).  Missing fraction is treated as zero.  Computed in LLI and
   --  clamped to Integer'Last so an oversized field cannot overflow the result.
   ---------------------------------------------------------------------------

   function Scaled (S : String; Places : Natural) return Natural with
     Pre => Places <= 9 and then S'Last <= Integer'Last - 1
   is
      Dot : Integer := 0;
      V   : LLI;
   begin
      if S = "" then
         return 0;
      end if;
      for I in S'Range loop
         pragma Loop_Invariant (Dot = 0 or else Dot in S'First .. S'Last);
         if S (I) = '.' then
            Dot := I;
         end if;
      end loop;
      if Dot = 0 then
         V := LLI (To_Nat (S)) * Pow10 (Places);
      else
         V := LLI (To_Nat (S (S'First .. Dot - 1))) * Pow10 (Places)
            + LLI (Frac (S (Dot + 1 .. S'Last), Places));
      end if;
      if V > LLI (Integer'Last) then
         return Integer'Last;
      end if;
      return Natural (V);
   end Scaled;

   ---------------------------------------------------------------------------
   --  NMEA coordinate "ddmm.mmmmm" + hemisphere -> 1e-7 degrees, signed.
   --  The two integer digits before the dot are minutes; everything before that
   --  is degrees (2 for latitude, 3 for longitude -- handled the same way).
   ---------------------------------------------------------------------------

   function Coord (S : String; Hemi : Character) return Interfaces.Integer_32 with
     Pre => S'Last <= Integer'Last - 1
   is
      Dot     : Integer := 0;
      Degrees : Natural;
      Min_E5  : LLI;        --  minutes in units of 1e-5 minute
      Deg_E7  : LLI;
   begin
      if S = "" then
         return 0;
      end if;
      for I in S'Range loop
         pragma Loop_Invariant (Dot = 0 or else Dot in S'First .. S'Last);
         if S (I) = '.' then
            Dot := I;
         end if;
      end loop;
      if Dot = 0 or else Dot - S'First < 3 then
         return 0;          --  too short to hold dd + mm.
      end if;

      Degrees := To_Nat (S (S'First .. Dot - 3));
      Min_E5  := LLI (To_Nat (S (Dot - 2 .. Dot - 1))) * 100_000
                 + LLI (Frac (S (Dot + 1 .. S'Last), 5));
      --  1e-5 minute = (1e7 / 60) / 1e5 deg_e7 = 5/3 deg_e7.
      Deg_E7 := LLI (Degrees) * 10_000_000 + (Min_E5 * 5) / 3;

      if Hemi = 'S' or else Hemi = 'W' then
         Deg_E7 := -Deg_E7;
      end if;
      --  Clamp into Integer_32 so a hostile, oversized degrees field cannot raise
      --  on the narrowing conversion (a real coordinate is well inside the range).
      if Deg_E7 > LLI (Interfaces.Integer_32'Last) then
         Deg_E7 := LLI (Interfaces.Integer_32'Last);
      elsif Deg_E7 < LLI (Interfaces.Integer_32'First) then
         Deg_E7 := LLI (Interfaces.Integer_32'First);
      end if;
      return Interfaces.Integer_32 (Deg_E7);
   end Coord;

   --  "hhmmss.ss" -> UTC_Time.
   function To_Time (S : String) return UTC_Time with
     Pre => S'Last <= Integer'Last - 1
   is
      T   : UTC_Time;
      Dot : Integer := 0;
   begin
      if S'Length < 6 then
         return T;
      end if;
      T.Hour   := To_Nat (S (S'First     .. S'First + 1));
      T.Minute := To_Nat (S (S'First + 2 .. S'First + 3));
      T.Second := To_Nat (S (S'First + 4 .. S'First + 5));
      for I in S'Range loop
         pragma Loop_Invariant (Dot = 0 or else Dot in S'First .. S'Last);
         if S (I) = '.' then
            Dot := I;
         end if;
      end loop;
      if Dot /= 0 then
         T.Centi := Frac (S (Dot + 1 .. S'Last), 2);
      end if;
      return T;
   end To_Time;

   --  "ddmmyy" -> Date (year 2000+yy).
   function To_Date (S : String) return Date is
      D : Date;
   begin
      if S'Length < 6 then
         return D;
      end if;
      D.Day   := To_Nat (S (S'First     .. S'First + 1));
      D.Month := To_Nat (S (S'First + 2 .. S'First + 3));
      D.Year  := 2000 + To_Nat (S (S'First + 4 .. S'First + 5));
      return D;
   end To_Date;

   ---------------------------------------------------------------------------
   --  Checksum: XOR of the bytes between '$' and '*', compared to the two hex
   --  digits after '*'.  Returns the payload slice (between '$' and '*') and
   --  whether it validated.
   ---------------------------------------------------------------------------

   procedure Check
     (Sentence : String; First, Last : out Integer; Ok : out Boolean)
   with Post => (if Ok then First = Sentence'First + 1
                          and then Last <= Sentence'Last
                          and then First <= Last + 1)
   is
      Star : Integer := 0;
      Sum  : Interfaces.Unsigned_8 := 0;
      Hi, Lo : Integer;
   begin
      First := 0; Last := -1; Ok := False;
      if Sentence'Length < 4 or else Sentence (Sentence'First) /= '$' then
         return;
      end if;
      for I in Sentence'First + 1 .. Sentence'Last loop
         if Sentence (I) = '*' then
            Star := I;
            exit;
         end if;
         Sum := Sum xor Interfaces.Unsigned_8 (Character'Pos (Sentence (I)));
      end loop;
      --  Written as "Star > Sentence'Last - 2" (not "Star + 2 > Sentence'Last")
      --  so the guard itself cannot overflow; Length >= 4 makes the subtraction
      --  safe, and on success Star + 2 is provably within Sentence'Range.
      if Star = 0 or else Star > Sentence'Last - 2 then
         return;   --  no '*HH'
      end if;
      Hi := Hex_Val (Sentence (Star + 1));
      Lo := Hex_Val (Sentence (Star + 2));
      if Hi < 0 or else Lo < 0 then
         return;
      end if;
      First := Sentence'First + 1;
      Last  := Star - 1;
      Ok    := Interfaces.Unsigned_8 (Hi * 16 + Lo) = Sum;
   end Check;

   --  Does talker+type field T end with the 3-letter sentence type Kind?
   function Is_Type (T : String; Kind : String) return Boolean is
     (T'Length >= 3 and then T (T'Last - 2 .. T'Last) = Kind);

   --  Constellation from a sentence's two-letter talker prefix.
   function System_Of (Kind : String) return GNSS_System is
      T : constant String :=
        (if Kind'Length >= 2 then Kind (Kind'First .. Kind'First + 1) else "");
   begin
      if    T = "GP" then return GPS;
      elsif T = "GL" then return GLONASS;
      elsif T = "GA" then return Galileo;
      elsif T = "GB" or else T = "BD" then return BeiDou;
      elsif T = "GQ" then return QZSS;
      else  return Other;
      end if;
   end System_Of;

   -----------
   -- Parse --
   -----------

   procedure Parse (Sentence : String; Result : out Parsed) is
      First, Last : Integer;
      Ok          : Boolean;
   begin
      Result := (others => <>);
      Check (Sentence, First, Last, Ok);
      if not Ok then
         return;
      end if;

      declare
         P    : constant String := Sentence (First .. Last);
         Kind : constant String := Field (P, 0);
      begin
         if Is_Type (Kind, "GGA") then
            --  $..GGA,time,lat,N/S,lon,E/W,qual,sats,hdop,alt,M,...
            Result.Recognised := True;
            declare
               Tm   : constant String := Field (P, 1);
               La   : constant String := Field (P, 2);
               Ns   : constant String := Field (P, 3);
               Lo   : constant String := Field (P, 4);
               Ew   : constant String := Field (P, 5);
               Q    : constant Natural := To_Nat (Field (P, 6));
               Sats : constant String := Field (P, 7);
               Alt  : constant String := Field (P, 9);
            begin
               if Tm /= "" then
                  Result.Has_Time := True;
                  Result.Time := To_Time (Tm);
               end if;
               Result.Has_Quality := True;
               Result.Quality :=
                 (case Q is
                     when 1      => GPS_Fix,
                     when 2      => DGPS_Fix,
                     when others => No_Fix);
               Result.Fix_Valid := Q > 0;
               if Sats /= "" then
                  Result.Has_Sats := True;
                  Result.Satellites := To_Nat (Sats);
               end if;
               if Alt /= "" then
                  Result.Has_Altitude := True;
                  Result.Altitude_MM := Scaled (Alt, 3);
               end if;
               if Result.Fix_Valid and then La /= "" and then Lo /= "" then
                  Result.Has_Position := True;
                  Result.Pos := (Latitude  => Coord (La, (if Ns = "" then 'N'
                                                          else Ns (Ns'First))),
                                 Longitude => Coord (Lo, (if Ew = "" then 'E'
                                                          else Ew (Ew'First))));
               end if;
            end;

         elsif Is_Type (Kind, "RMC") then
            --  $..RMC,time,status,lat,N/S,lon,E/W,speed,course,date,...
            Result.Recognised := True;
            declare
               Tm  : constant String := Field (P, 1);
               St  : constant String := Field (P, 2);
               La  : constant String := Field (P, 3);
               Ns  : constant String := Field (P, 4);
               Lo  : constant String := Field (P, 5);
               Ew  : constant String := Field (P, 6);
               Spd : constant String := Field (P, 7);   --  knots
               Cog : constant String := Field (P, 8);   --  degrees true
               Dt  : constant String := Field (P, 9);   --  ddmmyy
            begin
               Result.Fix_Valid := St = "A";
               if Tm /= "" then
                  Result.Has_Time := True;
                  Result.Time := To_Time (Tm);
               end if;
               if Dt /= "" then
                  Result.Has_Date := True;
                  Result.Day := To_Date (Dt);
               end if;
               if Result.Fix_Valid and then La /= "" and then Lo /= "" then
                  Result.Has_Position := True;
                  Result.Pos := (Latitude  => Coord (La, (if Ns = "" then 'N'
                                                          else Ns (Ns'First))),
                                 Longitude => Coord (Lo, (if Ew = "" then 'E'
                                                          else Ew (Ew'First))));
               end if;
               if Result.Fix_Valid and then (Spd /= "" or else Cog /= "") then
                  Result.Has_Velocity := True;
                  --  knots -> mm/s : 1 knot = 1852/3600 m/s.  Spd is milli-knots.
                  Result.Speed_MMS :=
                    Natural (LLI (Scaled (Spd, 3)) * 1852 / 3600);
                  Result.Course_CDeg := Scaled (Cog, 2);   --  centi-degrees
               end if;
            end;

         elsif Is_Type (Kind, "ZDA") then
            --  $..ZDA,hhmmss.ss,dd,mm,yyyy,zonehh,zonemm -- UTC time + date,
            --  NOT gated on a fix, so it updates the clock before lock.  The
            --  year is the full 4 digits here (unlike RMC's ddmmyy).
            Result.Recognised := True;
            declare
               Tm : constant String := Field (P, 1);
               Dd : constant String := Field (P, 2);
               Mm : constant String := Field (P, 3);
               Yy : constant String := Field (P, 4);
            begin
               if Tm /= "" then
                  Result.Has_Time := True;
                  Result.Time := To_Time (Tm);
               end if;
               if Dd /= "" and then Mm /= "" and then Yy /= "" then
                  Result.Has_Date := True;
                  Result.Day := (Day   => To_Nat (Dd),
                                 Month => To_Nat (Mm),
                                 Year  => To_Nat (Yy));
               end if;
            end;

         elsif Is_Type (Kind, "GLL") then
            --  $..GLL,lat,N/S,lon,E/W,hhmmss.ss,status,mode
            Result.Recognised := True;
            declare
               La : constant String := Field (P, 1);
               Ns : constant String := Field (P, 2);
               Lo : constant String := Field (P, 3);
               Ew : constant String := Field (P, 4);
               Tm : constant String := Field (P, 5);
               St : constant String := Field (P, 6);
            begin
               Result.Fix_Valid := St = "A";
               if Tm /= "" then
                  Result.Has_Time := True;
                  Result.Time := To_Time (Tm);
               end if;
               if Result.Fix_Valid and then La /= "" and then Lo /= "" then
                  Result.Has_Position := True;
                  Result.Pos := (Latitude  => Coord (La, (if Ns = "" then 'N'
                                                          else Ns (Ns'First))),
                                 Longitude => Coord (Lo, (if Ew = "" then 'E'
                                                          else Ew (Ew'First))));
               end if;
            end;

         elsif Is_Type (Kind, "VTG") then
            --  $..VTG,course_true,T,course_mag,M,speed_kn,N,speed_kmh,K,mode
            --  Velocity only.  The NMEA 2.3+ mode field (9) reports 'N' when the
            --  data is invalid; absent mode is treated as valid.
            Result.Recognised := True;
            declare
               Cog  : constant String := Field (P, 1);   --  true course, degrees
               Spd  : constant String := Field (P, 5);   --  knots
               Mode : constant String := Field (P, 9);   --  may be absent
            begin
               if Mode /= "N" and then (Spd /= "" or else Cog /= "") then
                  Result.Has_Velocity := True;
                  Result.Speed_MMS :=
                    Natural (LLI (Scaled (Spd, 3)) * 1852 / 3600);
                  Result.Course_CDeg := Scaled (Cog, 2);
               end if;
            end;

         elsif Is_Type (Kind, "GSV") then
            --  $..GSV,total,msg#,in_view,{prn,elev,azim,snr} x up to 4[,signalId]
            --  Read only as many satellite blocks as this message actually holds
            --  (derived from in_view + message number) -- otherwise a trailing
            --  NMEA-4.10 signalId field is misread as a PRN.
            Result.Recognised := True;
            declare
               Msg_No : constant Natural := To_Nat (Field (P, 2));
               View   : constant String := Field (P, 3);
               In_V   : constant Natural := To_Nat (View);
               Sys    : constant GNSS_System := System_Of (Kind);
               --  Satellites carried by earlier messages.  Computed so the "* 4"
               --  cannot overflow: only when (Msg_No - 1) <= In_V / 4 is the real
               --  product taken; past that the message is beyond the in-view set,
               --  so Before is forced above In_V and Here collapses to 0.
               Before : constant Natural :=
                 (if Msg_No >= 1 and then Msg_No - 1 <= In_V / 4
                  then 4 * (Msg_No - 1) else In_V + 1);
               Here   : constant Natural :=
                 (if In_V > Before then Natural'Min (4, In_V - Before) else 0);
               Best   : Natural := 0;
               N      : Natural := 0;
            begin
               if View /= "" then
                  Result.In_View := In_V;
               end if;
               for K in 0 .. Here - 1 loop
                  pragma Loop_Invariant (N <= K and then N <= 4);
                  declare
                     Prn : constant String := Field (P, 4 + 4 * K);
                     Elv : constant String := Field (P, 5 + 4 * K);
                     Azm : constant String := Field (P, 6 + 4 * K);
                     Snr : constant String := Field (P, 7 + 4 * K);
                  begin
                     if Prn /= "" then
                        N := N + 1;
                        Result.Sats (N) := (System    => Sys,
                                            PRN       => To_Nat (Prn),
                                            Elevation => To_Nat (Elv),
                                            Azimuth   => To_Nat (Azm),
                                            SNR       => To_Nat (Snr));
                        if Snr /= "" then
                           Best := Natural'Max (Best, To_Nat (Snr));
                        end if;
                     end if;
                  end;
               end loop;
               Result.Sat_Count := N;
               Result.Max_SNR := Best;
               Result.Has_Sky := View /= "" or else N > 0;
            end;

         elsif Is_Type (Kind, "GSA") then
            --  $..GSA,mode,fixtype,{prn} x12,PDOP,HDOP,VDOP
            Result.Recognised := True;
            declare
               FT : constant Natural := To_Nat (Field (P, 2));
               N  : Natural := 0;
            begin
               Result.Has_DOP := True;
               Result.Mode := (case FT is
                                  when 2      => Fix_2D,
                                  when 3      => Fix_3D,
                                  when others => Fix_None);
               for K in 3 .. 14 loop
                  pragma Loop_Invariant (N <= K - 3);
                  if Field (P, K) /= "" then
                     N := N + 1;
                  end if;
               end loop;
               Result.Used   := N;
               Result.PDOP_C := Scaled (Field (P, 15), 2);
               Result.HDOP_C := Scaled (Field (P, 16), 2);
               Result.VDOP_C := Scaled (Field (P, 17), 2);
            end;
         end if;
      end;
   end Parse;

end ESP32S3.GPS.NMEA;
