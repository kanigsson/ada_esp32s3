--  What it demonstrates
--    Reading an SD card on the bare-metal ESP32-S3 on a board where the card's
--    DAT3/CD line is wired not to the SoC but to a CH422G I2C expander pin, so
--    two reusable HAL drivers work together:
--      * ESP32S3.CH422G drives the card's DAT3/CD high via its IO4 pin -- needed
--        so the card enters/stays in SD mode.  The CH422G's IO direction is
--        GLOBAL, so making IO4 an output turns the whole bank to outputs; we load
--        the output register (IO4 high, the rest low) BEFORE enabling outputs, so
--        DAT3 is already high the instant the bank switches to drive (no glitch).
--        DAT3 is set once and never toggled, so the slow I2C path is fine.
--      * ESP32S3.SDMMC then talks to the card in 1-bit mode (DAT1/2/3 not wired).
--    READ-ONLY: it identifies the card, decodes CID/CSD/SCR (maker, product,
--    serial, date, capacity, spec version, capabilities), negotiates High-Speed
--    (50 MHz), and reads block 0 (checking the 0x55AA boot signature) -- it never
--    writes, so no card content can be lost.
--
--  Build & run
--    ./x run esp32s3_sdmmc_ch422g   (embedded profile; build.sh sets it)
--
--  Output
--    The expander result, the card identity/capacity/capabilities, and the
--    block-0 boot-signature check, printed over the ROM esp_rom_printf glue.
--
--  Hardware
--    An SD card in the slot.  I2C0 to the CH422G on SDA=IO8 / SCL=IO9; SDMMC
--    1-bit bus on CLK=IO12, CMD=IO11, D0=IO13.
with System;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.CH422G;
with ESP32S3.SDMMC;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package CH422G renames ESP32S3.CH422G;
   package SDMMC  renames ESP32S3.SDMMC;
   use type CH422G.Status;
   use type SDMMC.Status;

   procedure Banner;  pragma Import (C, Banner, "native_sd_banner");
   procedure Exio_R (Ok : int);  pragma Import (C, Exio_R, "native_sd_exio");
   procedure Init_R (Status, Kind : int);
                     pragma Import (C, Init_R, "native_sd_init");
   procedure Read_R (Status, B0, B1, B2, B3, Sig_Ok : int);
                     pragma Import (C, Read_R, "native_sd_read");
   procedure Id_C (Mid : int; Oem, Pnm : System.Address;
                   Rmaj, Rmin : int; Serial : unsigned; Year, Month : int);
                     pragma Import (C, Id_C, "native_sd_id");
   procedure Cap_C (Mb : unsigned);  pragma Import (C, Cap_C, "native_sd_cap");
   procedure Caps_C (Max_Mhz : int; Ccc : unsigned; Rbl : int;
                     Spec_Maj, Spec_Min, Bus4, Hs : int);
                     pragma Import (C, Caps_C, "native_sd_caps");
   procedure Speed_C (Active_Mhz, Hs_Active : int);
                     pragma Import (C, Speed_C, "native_sd_speed");
   procedure Done;  pragma Import (C, Done, "native_sd_done");

   --  Replace non-printable bytes (CID strings are ASCII, but be safe).
   function Clean (S : String) return String is
      Result : String := S;
   begin
      for I in Result'Range loop
         if Character'Pos (Result (I)) not in 32 .. 126 then
            Result (I) := '?';
         end if;
      end loop;
      return Result;
   end Clean;

   --  The CH422G I2C expander that drives the card's DAT3/CD line.
   Expander         : CH422G.Device;
   Expander_Session : CH422G.Session;
   Expander_Status  : CH422G.Status;

   --  The SD card and a scratch block for the boot-sector read.
   Card        : SDMMC.Card;
   Card_Status : SDMMC.Status;
   Block       : SDMMC.Block;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  1) CH422G: drive DAT3/CD (IO4) high.  Load the IO output register first
   --     (IO4=1, all other IO low), THEN enable outputs, so DAT3 never glitches
   --     low.  The Session is held for the whole run (the output latches anyway).
   CH422G.Setup (Expander, Sda => 8, Scl => 9);
   CH422G.Acquire (Expander_Session, Expander);
   CH422G.Write_IO (Expander_Session, 16#10#, Expander_Status);   --  IO4 high, rest low
   if Expander_Status = CH422G.OK then
      CH422G.Configure (Expander_Session,
                        IO_Dir => CH422G.Outputs, OC_Mode => CH422G.Push_Pull,
                        Result => Expander_Status);   --  enable outputs -> DAT3 high
   end if;
   Exio_R (Boolean'Pos (Expander_Status = CH422G.OK));

   --  2) SDMMC: 1-bit bus on CLK=IO12, CMD=IO11, D0=IO13 (D1/D2/D3 not wired).
   SDMMC.Setup (Card, On => SDMMC.Slot1, Clk => 12, Cmd => 11, D0 => 13,
                Width => SDMMC.Width_1,
                Init_Clock_Hz => 400_000, Data_Clock_Hz => 50_000_000,
                High_Speed => True);   --  negotiate the fastest the card allows

   SDMMC.Initialize (Card, Card_Status);
   Init_R (int (SDMMC.Status'Pos (Card_Status)),
           int (SDMMC.Card_Kind'Pos (SDMMC.Kind (Card))));

   --  Decoded identity (CID) + capacity (CSD).
   if Card_Status = SDMMC.OK then
      declare
         Id   : constant SDMMC.Card_Id := SDMMC.Identity (Card);
         Cap  : constant Interfaces.Unsigned_64 := SDMMC.Capacity_Blocks (Card);
         Caps : constant SDMMC.Card_Caps := SDMMC.Capabilities (Card);
         Oem  : aliased constant String := Clean (Id.OEM) & Character'Val (0);
         Pnm  : aliased constant String := Clean (Id.Product) & Character'Val (0);
      begin
         Id_C (int (Id.Manufacturer), Oem'Address, Pnm'Address,
               int (Id.Revision_Major), int (Id.Revision_Minor),
               unsigned (Id.Serial), int (Id.Mfg_Year), int (Id.Mfg_Month));
         Cap_C (unsigned (Cap / 2048));     --  blocks -> MB
         Caps_C (int (Caps.Max_Speed_MHz), unsigned (Caps.Command_Classes),
                 int (Caps.Read_Block_Len), int (Caps.Spec_Major),
                 int (Caps.Spec_Minor), Boolean'Pos (Caps.Supports_4bit),
                 Boolean'Pos (Caps.High_Speed));
         Speed_C (int (SDMMC.Active_Clock_Hz (Card) / 1_000_000),
                  Boolean'Pos (SDMMC.High_Speed_Active (Card)));
      end;
   end if;

   --  3) Read block 0 and check the boot signature (read-only).
   if Card_Status = SDMMC.OK then
      SDMMC.Read_Block (Card, 0, Block, Card_Status);
      Read_R (int (SDMMC.Status'Pos (Card_Status)),
              int (Block (0)), int (Block (1)), int (Block (2)), int (Block (3)),
              Boolean'Pos (Card_Status = SDMMC.OK
                           and then Block (510) = 16#55#
                           and then Block (511) = 16#AA#));
   end if;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
