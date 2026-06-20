--  Ada native SD/MMC-host self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ================================================================
--  Exercises the reusable HAL driver ESP32S3.SDMMC: bring up the SDHOST
--  controller on Slot1 in 4-bit mode, print what the card is, then do a
--  NON-DESTRUCTIVE round-trip on one scratch sector -- read it, write the same
--  bytes back, read again, and check the re-read matches.  Because the bytes
--  written are what was just read, no card content is lost.
--
--  Wiring (default pins below -- route any free GPIOs; pull-ups on CMD/DATA):
--     CLK = GPIO14  CMD = GPIO15  D0 = GPIO2  D1 = GPIO4  D2 = GPIO12  D3 = GPIO13
--     card VDD = 3V3, VSS = GND.
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SDMMC;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;  pragma Import (C, Banner, "native_sdmmc_banner");
   procedure Init_R (Status, Kind, Width : int);
   pragma Import (C, Init_R, "native_sdmmc_init");
   procedure Read_R (Which, Status, B0, B1, B2, B3 : int);
   pragma Import (C, Read_R, "native_sdmmc_read");
   procedure Write_R (Status : int);  pragma Import (C, Write_R, "native_sdmmc_write");
   procedure Verify_R (Ok : int);     pragma Import (C, Verify_R, "native_sdmmc_verify");
   procedure Done;    pragma Import (C, Done, "native_sdmmc_done");

   use type ESP32S3.SDMMC.Status;
   use type ESP32S3.SDMMC.Block;

   Test_LBA : constant ESP32S3.SDMMC.Block_Address := 16#2000#;   --  sector 8192

   C    : ESP32S3.SDMMC.Card;
   St   : ESP32S3.SDMMC.Status;
   Orig : ESP32S3.SDMMC.Block;
   Back : ESP32S3.SDMMC.Block;

   procedure Report_Read (Which : int; S : ESP32S3.SDMMC.Status;
                          B : ESP32S3.SDMMC.Block) is
   begin
      Read_R (Which, int (ESP32S3.SDMMC.Status'Pos (S)),
              int (B (0)), int (B (1)), int (B (2)), int (B (3)));
   end Report_Read;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   ESP32S3.SDMMC.Setup
     (C, On => ESP32S3.SDMMC.Slot1,
      Clk => 14, Cmd => 15, D0 => 2, D1 => 4, D2 => 12, D3 => 13,
      Width => ESP32S3.SDMMC.Width_4,
      Init_Clock_Hz => 400_000, Data_Clock_Hz => 20_000_000);

   ESP32S3.SDMMC.Initialize (C, St);
   Init_R (int (ESP32S3.SDMMC.Status'Pos (St)),
           int (ESP32S3.SDMMC.Card_Kind'Pos (ESP32S3.SDMMC.Kind (C))), 4);

   if St = ESP32S3.SDMMC.OK then
      ESP32S3.SDMMC.Read_Block (C, Test_LBA, Orig, St);
      Report_Read (1, St, Orig);

      if St = ESP32S3.SDMMC.OK then
         ESP32S3.SDMMC.Write_Block (C, Test_LBA, Orig, St);
         Write_R (int (ESP32S3.SDMMC.Status'Pos (St)));

         if St = ESP32S3.SDMMC.OK then
            ESP32S3.SDMMC.Read_Block (C, Test_LBA, Back, St);
            Report_Read (2, St, Back);
            Verify_R (Boolean'Pos (St = ESP32S3.SDMMC.OK and then Orig = Back));
         end if;
      end if;
   end if;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
