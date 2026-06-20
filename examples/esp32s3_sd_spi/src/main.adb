--  Ada SD-card-over-SPI self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ================================================================
--  Exercises the reusable HAL driver ESP32S3.SD_SPI: bring up a card on SPI2,
--  print what it is, then do a NON-DESTRUCTIVE round-trip on one scratch
--  sector -- read it, write the very same bytes back, read again, and check the
--  re-read matches.  Because the data written back is what was just read, no
--  card content is lost, so this is safe to run on a card with data on it.
--
--  Wiring (default pins below -- edit to match your board / SD breakout):
--     SCLK = GPIO12   MOSI = GPIO11   MISO = GPIO13   CS = GPIO10
--     card VDD = 3V3, VSS = GND, 10k pull-up on MISO recommended.
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SD_SPI;
with ESP32S3.SPI;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;  pragma Import (C, Banner, "native_sd_banner");
   procedure Init_R (Status, Kind : int);  pragma Import (C, Init_R, "native_sd_init");
   procedure Read_R (Which, Status, B0, B1, B2, B3 : int);
   pragma Import (C, Read_R, "native_sd_read");
   procedure Write_R (Status : int);  pragma Import (C, Write_R, "native_sd_write");
   procedure Verify_R (Ok : int);     pragma Import (C, Verify_R, "native_sd_verify");
   procedure Done;    pragma Import (C, Done, "native_sd_done");

   use type ESP32S3.SD_SPI.Status;
   use type ESP32S3.SD_SPI.Block;

   --  A scratch sector to round-trip.  Far from the partition table / FAT so a
   --  card with a filesystem is left untouched (and we write back what we read).
   Test_LBA : constant ESP32S3.SD_SPI.Block_Address := 16#2000#;   --  sector 8192

   C    : ESP32S3.SD_SPI.Card;
   St   : ESP32S3.SD_SPI.Status;
   Orig : ESP32S3.SD_SPI.Block;
   Back : ESP32S3.SD_SPI.Block;

   procedure Report_Read (Which : int; S : ESP32S3.SD_SPI.Status;
                          B : ESP32S3.SD_SPI.Block) is
   begin
      Read_R (Which, int (ESP32S3.SD_SPI.Status'Pos (S)),
              int (B (0)), int (B (1)), int (B (2)), int (B (3)));
   end Report_Read;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   ESP32S3.SD_SPI.Setup
     (C, Host => ESP32S3.SPI.SPI2,
      Sclk => 12, Mosi => 11, Miso => 13, Cs => 10,
      Init_Clock_Hz => 400_000, Data_Clock_Hz => 8_000_000);

   ESP32S3.SD_SPI.Initialize (C, St);
   Init_R (int (ESP32S3.SD_SPI.Status'Pos (St)),
           int (ESP32S3.SD_SPI.Card_Kind'Pos (ESP32S3.SD_SPI.Kind (C))));

   if St = ESP32S3.SD_SPI.OK then
      ESP32S3.SD_SPI.Read_Block (C, Test_LBA, Orig, St);
      Report_Read (1, St, Orig);

      if St = ESP32S3.SD_SPI.OK then
         --  Write the SAME bytes back (non-destructive), then re-read.
         ESP32S3.SD_SPI.Write_Block (C, Test_LBA, Orig, St);
         Write_R (int (ESP32S3.SD_SPI.Status'Pos (St)));

         if St = ESP32S3.SD_SPI.OK then
            ESP32S3.SD_SPI.Read_Block (C, Test_LBA, Back, St);
            Report_Read (2, St, Back);
            Verify_R (Boolean'Pos (St = ESP32S3.SD_SPI.OK and then Orig = Back));
         end if;
      end if;
   end if;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
