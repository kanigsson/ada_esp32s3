with System;
with System.Machine_Code;     use System.Machine_Code;
with Ada.Unchecked_Conversion;
with ESP32S3_Registers;        use ESP32S3_Registers;
with ESP32S3_Registers.DMA;    use ESP32S3_Registers.DMA;
with ESP32S3_Registers.SYSTEM;

package body ESP32S3.GDMA is

   --  PERI_SEL value that DISCONNECTS a path from any peripheral.
   Disconnect_Sel : constant := 16#3F#;

   --  Memory-to-memory does NOT use the "invalid/disconnected" id -- it borrows
   --  a *free real* peripheral trigger slot (any of 0..9) together with
   --  MEM_TRANS_EN on the RX path.  Using 0x3F here leaves the channel
   --  disconnected and it never runs (that was the long mem2mem bug).  esp-idf
   --  picks the lowest free slot; we use 0 (mem2mem doesn't touch the real SPI2,
   --  the data path is the internal TX->RX loopback).
   M2M_Sel : constant := 0;

   --  PERI_SEL encoding for a bound peripheral (TRM: 0:SPI2 .. 9:RMT).
   function Peri_Sel (P : Peripheral) return UInt6 is
     (case P is
         when Mem2Mem => M2M_Sel,
         when SPI2    => 0,  when SPI3    => 1,  when UHCI0 => 2,
         when I2S0    => 3,  when I2S1    => 4,  when LCD_CAM => 5,
         when AES     => 6,  when SHA     => 7,  when ADC_DAC => 8,
         when RMT     => 9);

   ---------------------------------------------------------------------------
   --  Per-channel register overlay.
   --
   --  svd2ada flattened the five identical channel blocks into named _CH0.._CH4
   --  fields; the hardware is really a regular array (stride 0xC0, IN block at
   --  +0x00, OUT block at +0x60).  We re-impose that array here -- only the
   --  registers the driver touches are named, at their in-block offsets -- so a
   --  runtime Channel_Id indexes Channels (Id).
   ---------------------------------------------------------------------------

   type Channel_Regs is record
      IN_CONF0     : IN_CONF0_CH_Register;
      IN_INT_RAW   : IN_INT_RAW_CH_Register;
      IN_INT_CLR   : IN_INT_CLR_CH_Register;
      IN_LINK      : IN_LINK_CH_Register;
      IN_PERI_SEL  : IN_PERI_SEL_CH_Register;
      OUT_CONF0    : OUT_CONF0_CH_Register;
      OUT_INT_RAW  : OUT_INT_RAW_CH_Register;
      OUT_INT_CLR  : OUT_INT_CLR_CH_Register;
      OUT_LINK     : OUT_LINK_CH_Register;
      OUT_PERI_SEL : OUT_PERI_SEL_CH_Register;
   end record
     with Volatile;

   for Channel_Regs use record
      IN_CONF0     at 16#00# range 0 .. 31;
      IN_INT_RAW   at 16#08# range 0 .. 31;
      IN_INT_CLR   at 16#14# range 0 .. 31;
      IN_LINK      at 16#20# range 0 .. 31;
      IN_PERI_SEL  at 16#48# range 0 .. 31;
      OUT_CONF0    at 16#60# range 0 .. 31;
      OUT_INT_RAW  at 16#68# range 0 .. 31;
      OUT_INT_CLR  at 16#74# range 0 .. 31;
      OUT_LINK     at 16#80# range 0 .. 31;
      OUT_PERI_SEL at 16#A8# range 0 .. 31;
   end record;

   for Channel_Regs'Size use 16#C0# * 8;          --  192-byte channel stride
   for Channel_Regs'Object_Size use 16#C0# * 8;

   type Channel_Array is array (Channel_Id) of Channel_Regs;

   Channels : Channel_Array
     with Import, Volatile, Address => ESP32S3_Registers.DMA_Base;

   ---------------------------------------------------------------------------
   --  DMA descriptor (in-RAM linked-list node; 12 bytes, 4-byte aligned).
   ---------------------------------------------------------------------------

   type DW0_Field is record
      Size    : UInt12   := 0;    --  buffer capacity in bytes
      Length  : UInt12   := 0;    --  valid bytes (TX: set by us; RX: by HW)
      Rsv     : UInt4    := 0;
      Err_EOF : Boolean  := False;
      Rsv29   : Boolean  := False;
      Suc_EOF : Boolean  := False;  --  last node in the link
      Owner   : Boolean  := False;  --  True = owned by DMA engine
   end record;
   for DW0_Field use record
      Size    at 0 range  0 .. 11;
      Length  at 0 range 12 .. 23;
      Rsv     at 0 range 24 .. 27;
      Err_EOF at 0 range 28 .. 28;
      Rsv29   at 0 range 29 .. 29;
      Suc_EOF at 0 range 30 .. 30;
      Owner   at 0 range 31 .. 31;
   end record;
   for DW0_Field'Size use 32;

   type Descriptor is record
      W0     : DW0_Field;
      Buffer : System.Address;
      Next   : System.Address;
   end record
     with Alignment => 4;

   --  One TX (source) and one RX (destination) descriptor per channel.  Module
   --  level -> lands in .bss (internal SRAM), satisfying the 20-bit link addr.
   TX_Desc : array (Channel_Id) of aliased Descriptor;
   RX_Desc : array (Channel_Id) of aliased Descriptor;

   function Addr_To_U32 is
     new Ada.Unchecked_Conversion (System.Address, UInt32);

   --  Low 20 bits of an address, for the *LINK INLINK/OUTLINK_ADDR field.
   function Link_Addr (A : System.Address) return UInt20 is
     (UInt20 (Addr_To_U32 (A) and 16#F_FFFF#));

   --  Fill a one-node descriptor: whole buffer, last in link, DMA-owned.
   procedure Set_Desc
     (D : in out Descriptor; Buf : System.Address; Length : Natural) is
   begin
      D.W0     := (Size    => UInt12 (Length),
                   Length  => UInt12 (Length),
                   Suc_EOF => True,
                   Owner   => True,
                   others  => <>);
      D.Buffer := Buf;
      D.Next   := System.Null_Address;
   end Set_Desc;

   --------------------------------------------------------------------------
   --  Protected channel allocator.  Serialises Claim / Release and the
   --  one-time module bring-up, so concurrent tasks can never be handed the
   --  same channel.  The transfer operations need no lock: once you hold a
   --  channel, only you touch its registers and descriptors.
   --------------------------------------------------------------------------

   type Use_Map is array (Channel_Id) of Boolean;

   protected Pool is
      procedure Claim (Peri : Peripheral; Id : out Channel_Id; Ok : out Boolean);
      procedure Release (Id : Channel_Id);
   private
      In_Use : Use_Map := (others => False);
      Inited : Boolean := False;
   end Pool;

   protected body Pool is

      procedure Claim
        (Peri : Peripheral; Id : out Channel_Id; Ok : out Boolean)
      is
         use ESP32S3_Registers.SYSTEM;
      begin
         --  One-time module bring-up: clock on, reset pulse, AHB master reset.
         if not Inited then
            SYSTEM_Periph.PERIP_CLK_EN1.DMA_CLK_EN := True;
            SYSTEM_Periph.PERIP_RST_EN1.DMA_RST    := True;
            SYSTEM_Periph.PERIP_RST_EN1.DMA_RST    := False;
            DMA_Periph.MISC_CONF.CLK_EN         := True;
            DMA_Periph.MISC_CONF.AHBM_RST_INTER := True;
            DMA_Periph.MISC_CONF.AHBM_RST_INTER := False;
            Inited := True;
         end if;

         for C in Channel_Id loop
            if not In_Use (C) then
               In_Use (C) := True;

               --  Reset both paths, bind the peripheral, set mem2mem loopback.
               Channels (C).IN_CONF0.IN_RST   := True;
               Channels (C).IN_CONF0.IN_RST   := False;
               Channels (C).OUT_CONF0.OUT_RST := True;
               Channels (C).OUT_CONF0.OUT_RST := False;
               Channels (C).OUT_PERI_SEL.PERI_OUT_SEL := Peri_Sel (Peri);
               Channels (C).IN_PERI_SEL.PERI_IN_SEL   := Peri_Sel (Peri);
               Channels (C).IN_CONF0.MEM_TRANS_EN     := (Peri = Mem2Mem);

               Id := C;
               Ok := True;
               return;
            end if;
         end loop;

         Id := 0;
         Ok := False;          --  pool exhausted
      end Claim;

      procedure Release (Id : Channel_Id) is
      begin
         Channels (Id).IN_CONF0.MEM_TRANS_EN     := False;
         Channels (Id).IN_PERI_SEL.PERI_IN_SEL   := Disconnect_Sel;
         Channels (Id).OUT_PERI_SEL.PERI_OUT_SEL := Disconnect_Sel;
         In_Use (Id) := False;
      end Release;

   end Pool;

   -----------
   -- Claim --
   -----------

   procedure Claim (C : in out Channel; Peri : Peripheral) is
      Id : Channel_Id;
      Ok : Boolean;
   begin
      Release (C);                    --  free any channel C already held
      Pool.Claim (Peri, Id, Ok);
      if Ok then
         C.Id    := Id;
         C.Valid := True;
      end if;
   end Claim;

   --------------
   -- Is_Valid --
   --------------

   function Is_Valid (C : Channel) return Boolean is (C.Valid);

   -------------
   -- Release --
   -------------

   procedure Release (C : in out Channel) is
   begin
      if C.Valid then
         Pool.Release (C.Id);
         C.Valid := False;
      end if;
   end Release;

   --  Scope-exit / exception-unwind cleanup: return the channel if still held.
   overriding procedure Finalize (C : in out Channel) is
   begin
      Release (C);
   end Finalize;

   ----------
   -- Copy --
   ----------

   procedure Copy (C : Channel; Dst, Src : System.Address; Length : Natural) is
   begin
      if not C.Valid or else Length = 0 or else Length > Max_Transfer then
         return;
      end if;

      --  Source (OUT/TX) and destination (IN/RX) descriptors.
      Set_Desc (TX_Desc (C.Id), Src, Length);
      Set_Desc (RX_Desc (C.Id), Dst, Length);

      --  Clear the sticky completion / error flags from any previous transfer.
      Channels (C.Id).IN_INT_CLR.IN_DONE     := True;
      Channels (C.Id).IN_INT_CLR.IN_SUC_EOF  := True;
      Channels (C.Id).IN_INT_CLR.IN_DSCR_ERR := True;

      --  Barrier: the descriptors above are plain memory writes; make sure they
      --  have committed to SRAM before the DMA (a separate bus master) fetches
      --  them.
      Asm ("memw", Volatile => True, Clobber => "memory");

      --  Mount the links and kick both paths (RX first, then TX feeds it).
      Channels (C.Id).IN_LINK.INLINK_AUTO_RET := False;
      Channels (C.Id).OUT_LINK.OUTLINK_ADDR := Link_Addr (TX_Desc (C.Id)'Address);
      Channels (C.Id).IN_LINK.INLINK_ADDR   := Link_Addr (RX_Desc (C.Id)'Address);

      Channels (C.Id).IN_LINK.INLINK_START   := True;
      Channels (C.Id).OUT_LINK.OUTLINK_START := True;

      --  Wait (bounded) for the receive side to report success-EOF.
      declare
         Guard : Natural := 0;
      begin
         while not Channels (C.Id).IN_INT_RAW.IN_SUC_EOF
           and then Guard < 2_000_000
         loop
            Guard := Guard + 1;
         end loop;
      end;
   end Copy;

   -----------
   -- Start --
   -----------

   procedure Start (C : Channel; Dir : Direction;
                    Buffer : System.Address; Length : Natural) is
   begin
      if not C.Valid or else Length = 0 or else Length > Max_Transfer then
         return;
      end if;

      case Dir is
         when Mem_To_Periph =>                       --  OUT/TX path
            Set_Desc (TX_Desc (C.Id), Buffer, Length);
            Channels (C.Id).OUT_INT_CLR.OUT_DONE     := True;
            Channels (C.Id).OUT_INT_CLR.OUT_EOF      := True;
            Channels (C.Id).OUT_INT_CLR.OUT_DSCR_ERR := True;
            Asm ("memw", Volatile => True, Clobber => "memory");
            Channels (C.Id).OUT_LINK.OUTLINK_ADDR  :=
              Link_Addr (TX_Desc (C.Id)'Address);
            Channels (C.Id).OUT_LINK.OUTLINK_START := True;

         when Periph_To_Mem =>                       --  IN/RX path
            Set_Desc (RX_Desc (C.Id), Buffer, Length);
            Channels (C.Id).IN_INT_CLR.IN_DONE     := True;
            Channels (C.Id).IN_INT_CLR.IN_SUC_EOF  := True;
            Channels (C.Id).IN_INT_CLR.IN_DSCR_ERR := True;
            Asm ("memw", Volatile => True, Clobber => "memory");
            Channels (C.Id).IN_LINK.INLINK_AUTO_RET := False;
            Channels (C.Id).IN_LINK.INLINK_ADDR     :=
              Link_Addr (RX_Desc (C.Id)'Address);
            Channels (C.Id).IN_LINK.INLINK_START    := True;
      end case;
   end Start;

   ----------------
   -- Start_Loop --
   ----------------

   procedure Start_Loop (C : Channel; Buffer : System.Address; Length : Natural)
   is
   begin
      if not C.Valid or else Length = 0 or else Length > Max_Transfer then
         return;
      end if;

      --  Self-linked descriptor: Next points back to itself and Suc_EOF is
      --  clear, so the OUT engine walks it forever.  With OUT_AUTO_WRBACK off
      --  the engine never writes the descriptor back, so Owner stays True and
      --  every pass re-reads Buffer -- a hands-free repeating transfer.
      TX_Desc (C.Id).W0     := (Size    => UInt12 (Length),
                                Length  => UInt12 (Length),
                                Suc_EOF => False,
                                Owner   => True,
                                others  => <>);
      TX_Desc (C.Id).Buffer := Buffer;
      TX_Desc (C.Id).Next   := TX_Desc (C.Id)'Address;   --  loop to self

      Channels (C.Id).OUT_CONF0.OUT_AUTO_WRBACK := False;
      Channels (C.Id).OUT_INT_CLR.OUT_DONE     := True;
      Channels (C.Id).OUT_INT_CLR.OUT_EOF      := True;
      Channels (C.Id).OUT_INT_CLR.OUT_DSCR_ERR := True;
      Asm ("memw", Volatile => True, Clobber => "memory");
      Channels (C.Id).OUT_LINK.OUTLINK_ADDR  :=
        Link_Addr (TX_Desc (C.Id)'Address);
      Channels (C.Id).OUT_LINK.OUTLINK_START := True;
   end Start_Loop;

   ----------
   -- Done --
   ----------

   function Done (C : Channel; Dir : Direction) return Boolean is
   begin
      if not C.Valid then
         return True;
      end if;
      case Dir is
         when Mem_To_Periph => return Channels (C.Id).OUT_INT_RAW.OUT_EOF;
         when Periph_To_Mem => return Channels (C.Id).IN_INT_RAW.IN_SUC_EOF;
      end case;
   end Done;

   ----------
   -- Wait --
   ----------

   procedure Wait (C : Channel; Dir : Direction) is
      Guard : Natural := 0;
   begin
      while not Done (C, Dir) and then Guard < 2_000_000 loop
         Guard := Guard + 1;
      end loop;
   end Wait;

end ESP32S3.GDMA;
