--  Ada ext4-on-SD self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ========================================================
--  What it demonstrates:
--    The pure-Ada filesystem (ESP32S3.Ext4) mounting a real ext4 (or ext2/3)
--    SD card layered over the SD-over-SPI block driver, then reading a file --
--    SD init, mount (reporting the block size), and the first bytes of
--    /hello.txt.  No ESP-IDF, no FreeRTOS.
--
--  Build & run:
--    ./x run esp32s3_ext4
--    Built as the EMBEDDED profile (build.sh sets ESP32S3_RTS_PROFILE=embedded),
--    because the filesystem uses exceptions + finalization.
--
--  Output (over USB-Serial-JTAG, via the ROM esp_rom_printf glue):
--    With a wired ext4 card holding /hello.txt = "hello...":
--      [ext4] SD card init: OK
--      [ext4] mount: OK   block size = 4096
--      [ext4] read /hello.txt: OK   first bytes = 68 65 6c 6c
--      [ext4] done.
--    With NO card wired it prints "SD card init: FAILED" and stops cleanly --
--    the boot + SD + mount path still runs; only the OK lines need a real card.
--
--  Hardware:
--    An SD card breakout on SPI2 (edit the pin constants below to match yours):
--      SCLK = GPIO12   MOSI = GPIO11   MISO = GPIO13   CS = GPIO10   VDD = 3V3.
--    Card setup on a Linux host:
--      mkfs.ext4 /dev/sdX1   (or ext2/3); then put a file at /hello.txt
--    Reading a default mkfs.ext4 card works; WRITES need a NON-metadata_csum
--    filesystem.  The SD block driver itself is not yet on-card-verified (see
--    its README), so bring that up first.
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SD_SPI;
with ESP32S3.SPI;
with ESP32S3.Block_Dev;
with ESP32S3.Block_Dev.SD_SPI_Source;
with ESP32S3.Ext4;            use ESP32S3.Ext4;
with ESP32S3.Ext4.FS;
with ESP32S3.Ext4.Inode;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   --  Console report routines (the ROM esp_rom_printf glue, in glue.c).  These
   --  own the exact output strings; the booleans below choose OK vs FAILED.
   procedure Banner;
   pragma Import (C, Banner, "native_ext4_banner");
   procedure Card_Result (Status : int);
   pragma Import (C, Card_Result, "native_ext4_card");
   procedure Mount_Result (Ok, Block_Size : int);
   pragma Import (C, Mount_Result, "native_ext4_mount");
   procedure Read_Result (Ok, Byte0, Byte1, Byte2, Byte3 : int);
   pragma Import (C, Read_Result, "native_ext4_read");
   procedure Done;
   pragma Import (C, Done, "native_ext4_done");

   use type ESP32S3.SD_SPI.Status;

   --  SD-card breakout wiring on SPI2 (see the header).  Edit to your board.
   SD_Sclk : constant := 12;
   SD_Mosi : constant := 11;
   SD_Miso : constant := 13;
   SD_Cs   : constant := 10;

   --  Let the USB-Serial-JTAG console settle before the first line is printed.
   Console_Settle_Delay : constant Time_Span := Milliseconds (200);

   --  glue.c's status convention: 0 = OK, 1 = FAILED.
   Status_OK     : constant int := 0;
   Status_Failed : constant int := 1;

   --  glue.c's boolean convention for OK/FAILED lines: non-zero = OK.
   Result_OK     : constant int := 1;
   Result_Failed : constant int := 0;

   --  We read the file from its start into a small fixed buffer, and report
   --  only the first few bytes (glue.c prints exactly four: enough to recognise
   --  "hell" = 68 65 6c 6c).
   File_Start_Offset : constant U64     := 0;
   Read_Buffer_Size  : constant Natural := 16;   --  bytes read in one go

   Card        : aliased ESP32S3.SD_SPI.Card;
   Card_Status : ESP32S3.SD_SPI.Status;   --  SD init outcome (OK / error)
begin
   delay until Clock + Console_Settle_Delay;
   Banner;

   ESP32S3.SD_SPI.Setup
     (Card,
      Host => ESP32S3.SPI.SPI2,
      Sclk => SD_Sclk,
      Mosi => SD_Mosi,
      Miso => SD_Miso,
      Cs   => SD_Cs);
   ESP32S3.SD_SPI.Initialize (Card, Card_Status);
   Card_Result
     (if Card_Status = ESP32S3.SD_SPI.OK then Status_OK else Status_Failed);

   --  Only attempt the mount/read once the card itself answered.
   if Card_Status = ESP32S3.SD_SPI.OK then
      declare
         --  Present the card as a generic block device to the filesystem.
         Device : constant ESP32S3.Block_Dev.Device :=
                    ESP32S3.Block_Dev.SD_SPI_Source.Make (Card'Access);
         Mount  : ESP32S3.Ext4.FS.Mount;
      begin
         Mount.Open (Device, Read_Only => True);
         Mount_Result (Result_OK, int (Mount.Block_Size));

         declare
            File_Info  : ESP32S3.Ext4.Inode.Info;
            Read_Buf   : Byte_Array (0 .. Read_Buffer_Size - 1);
            Bytes_Read : Natural;
         begin
            Mount.Stat (Mount.Lookup ("/hello.txt"), File_Info);
            Mount.Read_File (File_Info, File_Start_Offset, Read_Buf, Bytes_Read);
            Read_Result
              (Result_OK,
               int (Read_Buf (0)),
               int (Read_Buf (1)),
               int (Read_Buf (2)),
               int (Read_Buf (3)));
         exception
            --  Lookup/stat/read failed (missing file, bad fs, I/O error).
            when others =>
               Read_Result (Result_Failed, 0, 0, 0, 0);
         end;
      exception
         --  Mounting failed (not an ext2/3/4 card, or an unreadable superblock).
         when others =>
            Mount_Result (Result_Failed, 0);
      end;
   end if;

   Done;

   --  Nothing left to do; idle forever rather than return into the runtime.
   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
