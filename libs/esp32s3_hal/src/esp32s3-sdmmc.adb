with Interfaces;                 use Interfaces;
with ESP32S3_Registers;          use ESP32S3_Registers;
with ESP32S3_Registers.SDHOST;   use ESP32S3_Registers.SDHOST;
with ESP32S3_Registers.SYSTEM;
with ESP32S3_Registers.GPIO;
with ESP32S3_Registers.IO_MUX;

package body ESP32S3.SDMMC is

   package GR renames ESP32S3_Registers.GPIO;
   package MX renames ESP32S3_Registers.IO_MUX;

   --  The card-clock source feeding the controller's CLKDIV (PLL160M on the S3).
   --  The card clock = Src_Hz / (2 * divider).  If your bring-up clocks come out
   --  wrong, this is the number to revisit.
   Src_Hz : constant := 160_000_000;

   --  GPIO-matrix signal indices (ESP32-S3 gpio_sig_map.h), per slot.
   type Dat_Sigs is array (0 .. 3) of Natural;
   type Sig_Set is record
      Cclk : Natural;                 --  card clock out
      Ccmd : Natural;                 --  command line (out = in, bidirectional)
      Cdat : Dat_Sigs;                --  data lines D0..D3 (out = in)
   end record;

   Sig : constant array (Slot) of Sig_Set :=
     (Slot1 => (Cclk => 172, Ccmd => 178, Cdat => (180, 181, 182, 183)),
      Slot2 => (Cclk => 173, Ccmd => 179, Cdat => (213, 214, 215, 216)));

   function Card_No (S : Slot) return Natural is (Slot'Pos (S));

   --  Raw views of the registers whose useful bits the SVD lumps into one field.
   RINT : UInt32
     with Volatile, Import, Address => SDHOST_Periph.RINTSTS'Address;
   CDIV : UInt32
     with Volatile, Import, Address => SDHOST_Periph.CLKDIV'Address;
   FIFO : UInt32
     with Volatile, Import, Address => SDHOST_Periph.BUFFIFO'Address;

   --  RINTSTS bit masks (DesignWare mobile-storage host).
   Int_Cmd_Done : constant UInt32 := 16#0004#;   --  command done
   Int_Data_Over: constant UInt32 := 16#0008#;   --  data transfer over (DTO)
   Int_RCRC     : constant UInt32 := 16#0040#;   --  response CRC error
   Int_DCRC     : constant UInt32 := 16#0080#;   --  data CRC error
   Int_RTO      : constant UInt32 := 16#0100#;   --  response timeout
   Int_DRTO     : constant UInt32 := 16#0200#;   --  data read timeout
   Int_HTO      : constant UInt32 := 16#0400#;   --  data starvation by host
   Int_FRUN     : constant UInt32 := 16#0800#;   --  FIFO under/overrun
   Int_EBE      : constant UInt32 := 16#8000#;   --  end-bit error
   Int_Resp_Err : constant UInt32 := 16#0002#;   --  response error
   Data_Err     : constant UInt32 := Int_DCRC or Int_DRTO or Int_HTO or
                                     Int_FRUN or Int_EBE;

   --  Per-operation response words, filled by Issue (guarded by Lock).
   R0, R1w, R2w, R3w : UInt32 := 0;

   type Resp_Kind is (No_Resp, Short_Resp, Short_NoCRC, Long_Resp);
   type Data_Dir  is (No_Data, Read_Data, Write_Data);

   --  Busy-poll bounds.  On real silicon the hardware short-circuits these (the
   --  CIU accepts in a few clocks; a missing card raises RTO within the response
   --  timeout), so they only bound the WORST case -- e.g. an unclocked
   --  controller -- keeping a no-card run to a few seconds instead of a hang.
   CIU_Spins   : constant := 30_000;     --  wait for CMD.START_CMD to clear
   Cmd_Spins   : constant := 30_000;     --  wait for command-done / RTO
   Data_Spins  : constant := 200_000;    --  wait for a FIFO word / DTO
   Busy_Spins  : constant := 500_000;    --  wait for the card to leave busy
   ACMD41_Tries: constant := 400;        --  ~SD spec's 1 s power-up budget

   ---------------------------------------------------------------------------
   --  GPIO-matrix routing (single-threaded, from Setup).
   ---------------------------------------------------------------------------

   --  Drive matrix signal Sig out onto Pad.
   procedure Route_Out (Pad : ESP32S3.GPIO.Pin_Id; S : Natural) is
      O : GR.FUNC_OUT_SEL_CFG_Register :=
            GR.GPIO_Periph.FUNC_OUT_SEL_CFG (Natural (Pad));
   begin
      ESP32S3.GPIO.Configure (Pad, Mode => ESP32S3.GPIO.Output,
                              Drive => ESP32S3.GPIO.Drive_Strong);
      O.OUT_SEL := GR.FUNC_OUT_SEL_CFG_OUT_SEL_Field (S);
      O.OEN_SEL := False;
      GR.GPIO_Periph.FUNC_OUT_SEL_CFG (Natural (Pad)) := O;
   end Route_Out;

   --  Enable Pad's input buffer (with pull-up) and feed it to matrix input Sig.
   procedure Route_In (S : Natural; Pad : ESP32S3.GPIO.Pin_Id) is
      Ix : constant Natural := Natural (Pad);
      P  : MX.GPIO_Register := MX.IO_MUX_Periph.GPIO (Ix);
   begin
      P.MCU_SEL := 1;
      P.FUN_IE  := True;
      P.FUN_WPU := True;                       --  SD lines idle high
      MX.IO_MUX_Periph.GPIO (Ix) := P;
      GR.GPIO_Periph.FUNC_IN_SEL_CFG (S) :=
        (IN_SEL => GR.FUNC_IN_SEL_CFG_IN_SEL_Field (Ix), SEL => True, others => <>);
   end Route_In;

   --  A bidirectional SD line: both driven out and sampled in, pulled up.
   procedure Route_Bidir (Pad : ESP32S3.GPIO.Pin_Id; S : Natural) is
   begin
      Route_Out (Pad, S);
      Route_In  (S, Pad);
   end Route_Bidir;

   ---------------------------------------------------------------------------
   --  Card-clock programming (the DW "update clock registers only" dance).
   ---------------------------------------------------------------------------

   --  Issue a bare clock-update command and wait for the CIU to take it.
   procedure Clock_Command (Slot_No : Natural) is
   begin
      SDHOST_Periph.CMD :=
        (UPDATE_CLOCK_REGISTERS_ONLY => True,
         WAIT_PRVDATA_COMPLETE       => True,
         CARD_NUMBER                 => CMD_CARD_NUMBER_Field (Slot_No),
         START_CMD                   => True,
         others                      => <>);
      for I in 1 .. 100_000 loop
         exit when not SDHOST_Periph.CMD.START_CMD;
      end loop;
   end Clock_Command;

   procedure Set_Card_Clock (Slot_No : Natural; Hz : Positive) is
      Div : Natural := Src_Hz / (2 * Hz);
   begin
      if Div < 1 then
         Div := 0;                             --  0 => bypass (cclk = source)
      elsif Div > 255 then
         Div := 255;
      end if;

      SDHOST_Periph.CLKENA.CCLK_ENABLE := 0;   --  stop the clock
      Clock_Command (Slot_No);

      CDIV := UInt32 (Div);               --  divider[0] in the low byte
      SDHOST_Periph.CLKSRC.CLKSRC := 0;        --  every card uses divider 0
      Clock_Command (Slot_No);

      SDHOST_Periph.CLKENA :=
        (CCLK_ENABLE => CLKENA_CCLK_ENABLE_Field (2 ** Slot_No),
         LP_ENABLE   => 0,                     --  keep the clock running when idle
         others      => <>);
      Clock_Command (Slot_No);
   end Set_Card_Clock;

   ---------------------------------------------------------------------------
   --  Command / response.
   ---------------------------------------------------------------------------

   --  Send one command and collect its response into R0..R3w.  Sets up the data
   --  path flags (BLKSIZ/BYTCNT are programmed by the caller before a data cmd).
   function Issue (Index   : Natural;
                   Arg     : UInt32;
                   Resp    : Resp_Kind;
                   Dir     : Data_Dir := No_Data;
                   Slot_No : Natural;
                   Init    : Boolean := False) return Status
   is
   begin
      --  Clear all raw interrupt bits (write 1 to clear).
      RINT := 16#FFFF#;

      SDHOST_Periph.CMDARG := Arg;
      SDHOST_Periph.CMD :=
        (INDEX                 => CMD_INDEX_Field (Index),
         RESPONSE_EXPECT       => Resp /= No_Resp,
         RESPONSE_LENGTH       => Resp = Long_Resp,
         CHECK_RESPONSE_CRC    => Resp in Short_Resp | Long_Resp,
         DATA_EXPECTED         => Dir /= No_Data,
         READ_WRITE            => Dir = Write_Data,
         WAIT_PRVDATA_COMPLETE => True,
         SEND_INITIALIZATION   => Init,
         CARD_NUMBER           => CMD_CARD_NUMBER_Field (Slot_No),
         START_CMD             => True,
         others                => <>);

      --  Wait for the CIU to load the command.
      for I in 1 .. CIU_Spins loop
         exit when not SDHOST_Periph.CMD.START_CMD;
      end loop;

      --  Wait for command done (or an error / timeout).
      for I in 1 .. Cmd_Spins loop
         exit when (RINT and (Int_Cmd_Done or Int_RTO)) /= 0;
      end loop;

      if (RINT and Int_RTO) /= 0 then
         RINT := Int_RTO or Int_Cmd_Done;
         return Cmd_Timeout;
      end if;
      if (RINT and Int_Cmd_Done) = 0 then
         --  Poll ran out with no response and no RTO (e.g. an unclocked CIU):
         --  treat as a timeout rather than reading a stale response register.
         return Cmd_Timeout;
      end if;
      if Resp in Short_Resp | Long_Resp and then (RINT and Int_RCRC) /= 0 then
         RINT := Int_RCRC or Int_Cmd_Done or Int_Resp_Err;
         return Cmd_CRC;
      end if;

      R0 := SDHOST_Periph.RESP0;
      if Resp = Long_Resp then
         R1w := SDHOST_Periph.RESP1;
         R2w := SDHOST_Periph.RESP2;
         R3w := SDHOST_Periph.RESP3;
      end if;
      RINT := Int_Cmd_Done or Int_Resp_Err;
      return OK;
   end Issue;

   --  Wait for the card to stop signalling busy (DATA0 held low after R1b/write).
   procedure Wait_Not_Busy is
   begin
      for I in 1 .. Busy_Spins loop
         exit when not SDHOST_Periph.STATUS.DATA_BUSY;
      end loop;
   end Wait_Not_Busy;

   ---------------------------------------------------------------------------
   --  PIO data transfer through the FIFO (no DMA).
   ---------------------------------------------------------------------------

   procedure Prepare_Data is
   begin
      SDHOST_Periph.CTRL.FIFO_RESET := True;
      for I in 1 .. 1000 loop
         exit when not SDHOST_Periph.CTRL.FIFO_RESET;
      end loop;
      SDHOST_Periph.BLKSIZ.BLOCK_SIZE := 512;
      SDHOST_Periph.BYTCNT := 512;
   end Prepare_Data;

   --  Pull 512 bytes (128 words, little-endian) out of the read FIFO.
   function Read_FIFO (Data : out Block) return Status is
      W : UInt32;
   begin
      for Word in 0 .. 127 loop
         declare
            Ready : Boolean := False;
         begin
            for I in 1 .. Cmd_Spins loop
               if (RINT and Data_Err) /= 0 then
                  RINT := Data_Err;
                  Data := (others => 0);
                  return Read_Error;
               end if;
               if not SDHOST_Periph.STATUS.FIFO_EMPTY then
                  Ready := True;
                  exit;
               end if;
            end loop;
            if not Ready then
               Data := (others => 0);
               return Read_Error;
            end if;
         end;
         W := FIFO;
         Data (Word * 4)     := Unsigned_8 (W and 16#FF#);
         Data (Word * 4 + 1) := Unsigned_8 (Shift_Right (W, 8)  and 16#FF#);
         Data (Word * 4 + 2) := Unsigned_8 (Shift_Right (W, 16) and 16#FF#);
         Data (Word * 4 + 3) := Unsigned_8 (Shift_Right (W, 24) and 16#FF#);
      end loop;

      --  Wait for the data-transfer-over flag.
      for I in 1 .. Cmd_Spins loop
         exit when (RINT and (Int_Data_Over or Data_Err)) /= 0;
      end loop;
      if (RINT and Data_Err) /= 0 then
         RINT := Data_Err or Int_Data_Over;
         return Read_Error;
      end if;
      RINT := Int_Data_Over;
      return OK;
   end Read_FIFO;

   --  Push 512 bytes (128 words) into the write FIFO.
   function Write_FIFO (Data : Block) return Status is
      W : UInt32;
   begin
      for Word in 0 .. 127 loop
         declare
            Ready : Boolean := False;
         begin
            for I in 1 .. Cmd_Spins loop
               if (RINT and Data_Err) /= 0 then
                  RINT := Data_Err;
                  return Write_Error;
               end if;
               if not SDHOST_Periph.STATUS.FIFO_FULL then
                  Ready := True;
                  exit;
               end if;
            end loop;
            if not Ready then
               return Write_Error;
            end if;
         end;
         W := UInt32 (Data (Word * 4))
              or Shift_Left (UInt32 (Data (Word * 4 + 1)),  8)
              or Shift_Left (UInt32 (Data (Word * 4 + 2)), 16)
              or Shift_Left (UInt32 (Data (Word * 4 + 3)), 24);
         FIFO := W;
      end loop;

      for I in 1 .. Cmd_Spins loop
         exit when (RINT and (Int_Data_Over or Data_Err)) /= 0;
      end loop;
      if (RINT and Data_Err) /= 0 then
         RINT := Data_Err or Int_Data_Over;
         return Write_Error;
      end if;
      RINT := Int_Data_Over;
      Wait_Not_Busy;                            --  card programs the block
      return OK;
   end Write_FIFO;

   ---------------------------------------------------------------------------
   --  Whole operations (run under Lock).
   ---------------------------------------------------------------------------

   --  Byte vs block addressing: SDHC uses the LBA directly, SDSC needs *512.
   function Addr_Of (C : Card; LBA : Block_Address) return UInt32 is
     (if C.Block_Addressed
      then UInt32 (LBA)
      else UInt32 (LBA) * 512);

   procedure Do_Initialize (C : in out Card; Result : out Status) is
      N         : constant Natural := Card_No (C.On);
      St        : Status;
      V2        : Boolean := False;
      Responded : Boolean := False;
      Ready     : Boolean := False;
      OCR_Arg   : UInt32;
   begin
      C.Kind := Unknown;
      C.Block_Addressed := False;

      Set_Card_Clock (N, C.Init_Hz);

      --  CMD0: 80 init clocks then go-idle (no response).
      St := Issue (0, 0, No_Resp, Slot_No => N, Init => True);

      --  CMD8: voltage check.  No response => v1 card; else confirm 0xAA echo.
      St := Issue (8, 16#1AA#, Short_Resp, Slot_No => N);
      V2 := (St = OK and then (R0 and 16#FF#) = 16#AA#);

      --  ACMD41 until the card powers up (OCR busy bit 31 set).
      OCR_Arg := (if V2 then 16#4030_0000# else 16#0030_0000#);   --  HCS + 3V3
      for Tries in 1 .. ACMD41_Tries loop
         St := Issue (55, 0, Short_Resp, Slot_No => N);
         St := Issue (41, OCR_Arg, Short_NoCRC, Slot_No => N);
         if St = OK then
            Responded := True;
            if (R0 and 16#8000_0000#) /= 0 then
               Ready := True;
               exit;
            end if;
         end if;
      end loop;

      if not Ready then
         Result := (if Responded then Init_Timeout else No_Card);
         return;
      end if;

      C.Block_Addressed := (R0 and 16#4000_0000#) /= 0;          --  CCS bit
      C.Kind := (if C.Block_Addressed then SDHC else SDSC);

      --  CMD2: read CID (long response, value discarded).
      St := Issue (2, 0, Long_Resp, Slot_No => N);

      --  CMD3: publish a relative card address (R6: RCA in the high half-word).
      St := Issue (3, 0, Short_Resp, Slot_No => N);
      if St /= OK then
         Result := St;
         return;
      end if;
      C.RCA := Unsigned_16 (Shift_Right (R0, 16) and 16#FFFF#);

      --  CMD7: select the card (R1b -> may go busy).
      St := Issue (7, Shift_Left (UInt32 (C.RCA), 16), Short_Resp,
                   Slot_No => N);
      Wait_Not_Busy;

      --  Optional 4-bit bus: ACMD6 then set the controller's card width.
      if C.Width = Width_4 then
         St := Issue (55, Shift_Left (UInt32 (C.RCA), 16), Short_Resp,
                      Slot_No => N);
         St := Issue (6, 2, Short_Resp, Slot_No => N);           --  bus width = 4
         SDHOST_Periph.CTYPE.CARD_WIDTH4 :=
           CTYPE_CARD_WIDTH4_Field (2 ** N);
      end if;

      --  CMD16: 512-byte blocks (required for SDSC, harmless for SDHC).
      St := Issue (16, 512, Short_Resp, Slot_No => N);

      Set_Card_Clock (N, C.Data_Hz);            --  switch to the fast clock
      Result := OK;
   end Do_Initialize;

   procedure Do_Read (C : in out Card; LBA : Block_Address;
                      Data : out Block; Result : out Status) is
      N  : constant Natural := Card_No (C.On);
      St : Status;
   begin
      Prepare_Data;
      St := Issue (17, Addr_Of (C, LBA), Short_Resp, Dir => Read_Data,
                   Slot_No => N);
      if St /= OK then
         Data := (others => 0);
         Result := St;
         return;
      end if;
      Result := Read_FIFO (Data);
   end Do_Read;

   procedure Do_Write (C : in out Card; LBA : Block_Address;
                       Data : Block; Result : out Status) is
      N  : constant Natural := Card_No (C.On);
      St : Status;
   begin
      Prepare_Data;
      St := Issue (24, Addr_Of (C, LBA), Short_Resp, Dir => Write_Data,
                   Slot_No => N);
      if St /= OK then
         Result := St;
         return;
      end if;
      Result := Write_FIFO (Data);
   end Do_Write;

   ---------------------------------------------------------------------------
   --  The single shared controller -- one protected object serialises it.
   ---------------------------------------------------------------------------

   protected Lock is
      procedure Initialize (C : in out Card; Result : out Status);
      procedure Read  (C : in out Card; LBA : Block_Address;
                       Data : out Block; Result : out Status);
      procedure Write (C : in out Card; LBA : Block_Address;
                       Data : Block; Result : out Status);
   end Lock;

   protected body Lock is
      procedure Initialize (C : in out Card; Result : out Status) is
      begin
         Do_Initialize (C, Result);
      end Initialize;

      procedure Read (C : in out Card; LBA : Block_Address;
                      Data : out Block; Result : out Status) is
      begin
         Do_Read (C, LBA, Data, Result);
      end Read;

      procedure Write (C : in out Card; LBA : Block_Address;
                       Data : Block; Result : out Status) is
      begin
         Do_Write (C, LBA, Data, Result);
      end Write;
   end Lock;

   ---------------------------------------------------------------------------
   --  Public API.
   ---------------------------------------------------------------------------

   procedure Setup (C             : out Card;
                    On            : Slot;
                    Clk, Cmd, D0  : ESP32S3.GPIO.Pin_Id;
                    D1, D2, D3    : ESP32S3.GPIO.Optional_Pin := ESP32S3.GPIO.No_Pin;
                    Width         : Bus_Width := Width_1;
                    Init_Clock_Hz : Positive := 400_000;
                    Data_Clock_Hz : Positive := 20_000_000)
   is
      use ESP32S3_Registers.SYSTEM;
      use type ESP32S3.GPIO.Pad_Number;
      S : constant Sig_Set := Sig (On);
      N : constant Natural := Card_No (On);
   begin
      C.On      := On;
      C.Width   := Width;
      C.Init_Hz := Init_Clock_Hz;
      C.Data_Hz := Data_Clock_Hz;
      C.Kind    := Unknown;
      C.RCA     := 0;
      C.Block_Addressed := False;

      --  Peripheral clock + release reset.
      SYSTEM_Periph.PERIP_CLK_EN1.SDIO_HOST_CLK_EN := True;
      SYSTEM_Periph.PERIP_RST_EN1.SDIO_HOST_RST    := True;
      SYSTEM_Periph.PERIP_RST_EN1.SDIO_HOST_RST    := False;

      --  Reset the controller, FIFO and DMA blocks.
      SDHOST_Periph.CTRL :=
        (CONTROLLER_RESET => True, FIFO_RESET => True, DMA_RESET => True,
         others => <>);
      for I in 1 .. 100_000 loop
         exit when not SDHOST_Periph.CTRL.CONTROLLER_RESET
           and then not SDHOST_Periph.CTRL.FIFO_RESET;
      end loop;

      --  Generous response/data timeouts; conservative FIFO watermarks.
      SDHOST_Periph.TMOUT := (RESPONSE_TIMEOUT => 16#FF#,
                              DATA_TIMEOUT => 16#FFFFFF#, others => <>);
      SDHOST_Periph.FIFOTH := (TX_WMARK => 8, RX_WMARK => 7,
                               DMA_MULTIPLE_TRANSACTION_SIZE => 0, others => <>);
      SDHOST_Periph.RST_N.CARD_RESET := RST_N_CARD_RESET_Field (2 ** N);
      SDHOST_Periph.CTYPE := (others => <>);    --  start 1-bit; widened at init
      SDHOST_Periph.INTMASK := (others => <>);  --  poll, no interrupts
      RINT := 16#FFFF#;                         --  clear stale raw ints

      --  Route the slot's lines through the GPIO matrix.
      Route_Out   (Clk, S.Cclk);                --  clock: output only
      Route_Bidir (Cmd, S.Ccmd);                --  command: bidirectional
      Route_Bidir (D0,  S.Cdat (0));
      if D1 /= ESP32S3.GPIO.No_Pin then
         Route_Bidir (ESP32S3.GPIO.Pin_Id (D1), S.Cdat (1));
      end if;
      if D2 /= ESP32S3.GPIO.No_Pin then
         Route_Bidir (ESP32S3.GPIO.Pin_Id (D2), S.Cdat (2));
      end if;
      if D3 /= ESP32S3.GPIO.No_Pin then
         Route_Bidir (ESP32S3.GPIO.Pin_Id (D3), S.Cdat (3));
      end if;

      --  Start the card clock slow for the identification phase.
      Set_Card_Clock (N, Init_Clock_Hz);
   end Setup;

   procedure Initialize (C : in out Card; Result : out Status) is
   begin
      Lock.Initialize (C, Result);
   end Initialize;

   function Kind (C : Card) return Card_Kind is (C.Kind);

   procedure Read_Block (C : in out Card; LBA : Block_Address;
                         Data : out Block; Result : out Status) is
   begin
      Lock.Read (C, LBA, Data, Result);
   end Read_Block;

   procedure Write_Block (C : in out Card; LBA : Block_Address;
                          Data : Block; Result : out Status) is
   begin
      Lock.Write (C, LBA, Data, Result);
   end Write_Block;

end ESP32S3.SDMMC;
