package body ESP32S3.TX1812 is

   use type ESP32S3.RMT.Tick_Count;

   --  RMT tick resolution and the four per-bit pulse widths.  At 10 MHz one tick
   --  is 100 ns; these widths are within the WS2812 / TX1812 tolerance (a '0' is
   --  a short high then long low, a '1' the reverse, ~1.2 us per bit).  Tune here
   --  if a particular part is fussy.
   Resolution_Hz : constant := 10_000_000;            --  100 ns / tick
   T0H : constant ESP32S3.RMT.Tick_Count := 3;        --  '0' high  300 ns
   T0L : constant ESP32S3.RMT.Tick_Count := 9;        --  '0' low   900 ns
   T1H : constant ESP32S3.RMT.Tick_Count := 7;        --  '1' high  700 ns
   T1L : constant ESP32S3.RMT.Tick_Count := 6;        --  '1' low   600 ns

   -------------
   -- Acquire --
   -------------

   procedure Acquire (S       : in out Strip;
                      Pin     : ESP32S3.GPIO.Pin_Id;
                      Channel : ESP32S3.RMT.TX_Index := 0) is
   begin
      ESP32S3.RMT.Claim (S.Chan, Channel);
      if ESP32S3.RMT.Is_Valid (S.Chan) then
         ESP32S3.RMT.Configure (S.Chan, Resolution_Hz => Resolution_Hz,
                                Pin => Pin);
         S.Ready := True;
      end if;
   end Acquire;

   --------------
   -- Is_Valid --
   --------------

   function Is_Valid (S : Strip) return Boolean is
     (S.Ready and then ESP32S3.RMT.Is_Valid (S.Chan));

   -------------
   -- Release --
   -------------

   procedure Release (S : in out Strip) is
   begin
      ESP32S3.RMT.Release (S.Chan);
      S.Ready := False;
   end Release;

   ---------
   -- Set --
   ---------

   procedure Set (S : in out Strip; Index : Positive; C : Color) is
   begin
      if Index in 1 .. S.Count then
         S.Pixels (Index) := C;
      end if;
   end Set;

   -------------
   -- Set_All --
   -------------

   procedure Set_All (S : in out Strip; C : Color) is
   begin
      S.Pixels := (others => C);
   end Set_All;

   ----------
   -- Show --
   ----------

   procedure Show (S : in out Strip) is
      Bits_Per_LED : constant := 24;
      Syms : ESP32S3.RMT.Symbol_Array (0 .. S.Count * Bits_Per_LED - 1);
      K    : Natural := 0;

      --  Append byte B's 8 bits, MSB first, as RMT symbols.
      procedure Emit (B : Unsigned_8) is
      begin
         for I in reverse 0 .. 7 loop
            if (B and Shift_Left (Unsigned_8 (1), I)) /= 0 then
               Syms (K) := (Level0 => True, Duration0 => T1H,
                            Level1 => False, Duration1 => T1L);
            else
               Syms (K) := (Level0 => True, Duration0 => T0H,
                            Level1 => False, Duration1 => T0L);
            end if;
            K := K + 1;
         end loop;
      end Emit;
   begin
      if not S.Ready then
         return;
      end if;
      --  TX1812 / WS2812 wire order is G, R, B.
      for P in 1 .. S.Count loop
         Emit (S.Pixels (P).G);
         Emit (S.Pixels (P).R);
         Emit (S.Pixels (P).B);
      end loop;
      ESP32S3.RMT.Transmit (S.Chan, Syms);
      --  The channel idles low after the burst; the >80 us before the next Show
      --  provides the reset that latches the new colours.
   end Show;

end ESP32S3.TX1812;
