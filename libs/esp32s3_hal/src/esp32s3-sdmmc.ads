with Interfaces;
with ESP32S3.GPIO;

--  ESP32-S3 native SD/MMC host (the dedicated SDHOST controller).
--
--  Unlike ESP32S3.SD_SPI (which talks to a card over the SPI master), this drives
--  the card on the real SD bus: a clock + bidirectional command line + 1 or 4
--  data lines, with the controller's own command/response state machine.  It is
--  faster than SPI mode and is how you reach an SDHC/SDXC card at speed.
--
--  Data moves in PIO/FIFO mode -- the CPU pushes/pops the 512-byte block through
--  the controller's data FIFO (BUFFIFO).  No GDMA, no descriptors, hence no
--  finalization: a library-level protected object serialises the single shared
--  controller, so this works under EVERY runtime profile (light-tasking too).
--
--  Wiring -- route any free GPIOs through the GPIO matrix (4 lines for 4-bit):
--     CLK (out)   CMD (bidir, pull-up)   D0..D3 (bidir, pull-ups)
--     card VDD = 3V3, VSS = GND.  Pull-ups (10k-50k) on CMD and every DATA line.
--  There are two card slots (Slot1 / Slot2); only one card per slot.
--
--  Cards init at <=400 kHz then run at Data_Clock_Hz.  The API is always 512-byte
--  logical blocks (LBA); SDHC/SDXC use block addressing, SDSC byte addressing,
--  resolved internally.
package ESP32S3.SDMMC is

   --  The controller's two card slots (distinct GPIO-matrix signals + clocks).
   type Slot is (Slot1, Slot2);

   --  Data-bus width.  1-bit needs only D0; 4-bit needs D0..D3.
   type Bus_Width is (Width_1, Width_4);

   --  A 512-byte logical block.
   type Block is array (0 .. 511) of Interfaces.Unsigned_8;

   --  Logical block address (sector number).
   type Block_Address is new Interfaces.Unsigned_32;

   --  What the card turned out to be (after Initialize).
   type Card_Kind is (Unknown, SDSC, SDHC);   --  SDHC also covers SDXC

   --  Result of an operation.
   type Status is
     (OK,
      No_Card,        --  no response to CMD0/ACMD41 (nothing there / not wired)
      Unusable,       --  CMD8 / OCR says not a usable 3V3 SD card
      Init_Timeout,   --  ACMD41 never reported ready
      Cmd_Timeout,    --  a command got no response (RTO)
      Cmd_CRC,        --  response CRC error (RCRC)
      Read_Error,     --  data read failed (DCRC / DRTO / FIFO)
      Write_Error);   --  data write / programming failed

   --  A single card on one slot.  Limited (non-copyable).  Holds no finalizable
   --  resource -- the shared controller is guarded by an internal protected
   --  object -- so no controlled type is needed.
   type Card is limited private;

   ----------------------------------------------------------------------------
   --  Configuration -- call once before Initialize (single-threaded).
   ----------------------------------------------------------------------------

   --  Bring the SDHOST controller up and route this slot's lines through the
   --  GPIO matrix.  D1..D3 may be left No_Pin for a 1-bit bus.  Init_Clock_Hz
   --  must be <= 400 kHz; Data_Clock_Hz is what Initialize switches to.
   procedure Setup (C             : out Card;
                    On            : Slot;
                    Clk, Cmd, D0  : ESP32S3.GPIO.Pin_Id;
                    D1, D2, D3    : ESP32S3.GPIO.Optional_Pin := ESP32S3.GPIO.No_Pin;
                    Width         : Bus_Width := Width_1;
                    Init_Clock_Hz : Positive := 400_000;
                    Data_Clock_Hz : Positive := 20_000_000);

   ----------------------------------------------------------------------------
   --  Operation.
   ----------------------------------------------------------------------------

   --  Run the card-identification sequence (CMD0/8, ACMD41, CMD2/3/9/7, bus
   --  width, block length).  On OK the card is selected and the bus raised to
   --  Data_Clock_Hz; Kind reports what it is.
   procedure Initialize (C : in out Card; Result : out Status);

   --  What Initialize found (Unknown until a successful Initialize).
   function Kind (C : Card) return Card_Kind;

   --  Read / write one 512-byte block at logical address LBA.
   procedure Read_Block  (C : in out Card; LBA : Block_Address;
                          Data : out Block; Result : out Status);
   procedure Write_Block (C : in out Card; LBA : Block_Address;
                          Data : Block; Result : out Status);

private
   type Card is limited record
      On              : Slot       := Slot1;
      Width           : Bus_Width  := Width_1;
      Init_Hz         : Positive   := 400_000;
      Data_Hz         : Positive   := 20_000_000;
      Kind            : Card_Kind  := Unknown;
      RCA             : Interfaces.Unsigned_16 := 0;   --  relative card address
      Block_Addressed : Boolean    := False;           --  True for SDHC/SDXC
   end record;
end ESP32S3.SDMMC;
