with ESP32S3.SPI.Engine;

package body ESP32S3.SPI is

   package E renames ESP32S3.SPI.Engine;

   --  One protected guard per host -- arbitrates exclusive ownership.  The
   --  guarded section is tiny (flip a flag); the actual transfer runs outside.
   protected type Host_Guard is
      entry    Acquire;
      procedure Release;
   private
      Held : Boolean := False;
   end Host_Guard;

   protected body Host_Guard is
      entry Acquire when not Held is
      begin
         Held := True;
      end Acquire;

      procedure Release is
      begin
         Held := False;
      end Release;
   end Host_Guard;

   Guards : array (SPI_Host) of Host_Guard;

   ----------------------------------------------------------------------------
   --  State -- the single, ownership-checked gateway to the raw register bus.
   --
   --  The per-host Bus array lives in this package's BODY, so nothing else in
   --  ESP32S3.SPI can name it.  Owned (S) is the ONLY export that returns a Bus,
   --  and it raises Not_Owned unless S currently holds the host -- so a transfer
   --  physically cannot reach the registers without proving ownership, and a new
   --  transfer op cannot be written that skips the check.  The startup config
   --  entries (Open/Set_Clock/Enable_Loopback/Configure_Pins) are host-keyed
   --  (single-threaded, pre-Acquire) and never hand a Bus back out.
   ----------------------------------------------------------------------------

   package State is
      procedure Open (Host : SPI_Host; Mode : SPI_Mode; Clock_Hz : Positive);
      procedure Set_Clock (Host : SPI_Host; Hz : Positive);
      procedure Enable_Loopback (Host : SPI_Host; Pad : ESP32S3.GPIO.Pin_Id);
      procedure Configure_Pins (Host : SPI_Host;
                                Sclk : ESP32S3.GPIO.Optional_Pin;
                                Mosi : ESP32S3.GPIO.Optional_Pin;
                                Miso : ESP32S3.GPIO.Optional_Pin;
                                Cs   : ESP32S3.GPIO.Optional_Pin);
      function  Ready (Host : SPI_Host) return Boolean;
      function  Owned (S : Session) return access E.Bus;
   end State;

   package body State is
      Buses     : array (SPI_Host) of aliased E.Bus;  --  raw bus per host, hidden
      Ready_Map : array (SPI_Host) of Boolean := (others => False);

      procedure Open (Host : SPI_Host; Mode : SPI_Mode; Clock_Hz : Positive) is
      begin
         E.Open (Buses (Host), Host, Mode, Clock_Hz);
         Ready_Map (Host) := True;
      end Open;

      procedure Set_Clock (Host : SPI_Host; Hz : Positive) is
      begin
         E.Set_Clock (Buses (Host), Hz);
      end Set_Clock;

      procedure Enable_Loopback (Host : SPI_Host; Pad : ESP32S3.GPIO.Pin_Id) is
      begin
         E.Enable_Loopback (Buses (Host), Pad);
      end Enable_Loopback;

      procedure Configure_Pins (Host : SPI_Host;
                                Sclk : ESP32S3.GPIO.Optional_Pin;
                                Mosi : ESP32S3.GPIO.Optional_Pin;
                                Miso : ESP32S3.GPIO.Optional_Pin;
                                Cs   : ESP32S3.GPIO.Optional_Pin) is
      begin
         E.Configure_Pins (Buses (Host), Sclk, Mosi, Miso, Cs);
      end Configure_Pins;

      function Ready (Host : SPI_Host) return Boolean is (Ready_Map (Host));

      function Owned (S : Session) return access E.Bus is
      begin
         if not S.Active then
            raise Not_Owned
              with "SPI host used without holding it -- Acquire first";
         end if;
         return Buses (S.Host)'Access;
      end Owned;
   end State;

   -----------
   -- Setup --
   -----------

   procedure Setup (Host     : SPI_Host;
                    Mode     : SPI_Mode := 0;
                    Clock_Hz : Positive := 1_000_000) is
   begin
      State.Open (Host, Mode, Clock_Hz);
   end Setup;

   procedure Set_Clock (Host : SPI_Host; Hz : Positive) is
   begin
      State.Set_Clock (Host, Hz);
   end Set_Clock;

   procedure Enable_Loopback (Host : SPI_Host; Pad : ESP32S3.GPIO.Pin_Id) is
   begin
      State.Enable_Loopback (Host, Pad);
   end Enable_Loopback;

   procedure Configure_Pins (Host : SPI_Host;
                             Sclk : ESP32S3.GPIO.Optional_Pin;
                             Mosi : ESP32S3.GPIO.Optional_Pin;
                             Miso : ESP32S3.GPIO.Optional_Pin;
                             Cs   : ESP32S3.GPIO.Optional_Pin := No_Pin) is
   begin
      State.Configure_Pins (Host, Sclk, Mosi, Miso, Cs);
   end Configure_Pins;

   -------------
   -- Acquire --
   -------------

   procedure Acquire (S : in out Session; Host : SPI_Host) is
   begin
      if not State.Ready (Host) then
         raise Not_Initialized with "SPI host acquired before Setup";
      end if;
      Guards (Host).Acquire;          --  suspends here until the host is free
      S.Host   := Host;
      S.Active := True;
   end Acquire;

   --------------
   -- Transfer --
   --------------

   procedure Transfer (S : Session; Tx, Rx : System.Address; Length : Natural) is
   begin
      --  Owned raises unless we hold the host; runs OUTSIDE the guard.
      E.Transfer (State.Owned (S).all, Tx, Rx, Length);
   end Transfer;

   -------------
   -- Release --
   -------------

   procedure Release (S : in out Session) is
   begin
      if S.Active then
         S.Active := False;
         Guards (S.Host).Release;
      end if;
   end Release;

   --  Scope-exit / exception-unwind cleanup: hand the host back if still held.
   overriding procedure Finalize (S : in out Session) is
   begin
      Release (S);
   end Finalize;

end ESP32S3.SPI;
