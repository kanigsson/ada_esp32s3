--  Ada ext4-on-SD self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ========================================================
--  Mounts a real ext4 (or ext2/3) SD card with the pure-Ada filesystem
--  (ESP32S3.Ext4) layered over the SD-over-SPI block driver, and reads a file.
--
--  Wiring (default pins -- edit to your board / SD breakout):
--     SCLK = GPIO12   MOSI = GPIO11   MISO = GPIO13   CS = GPIO10, VDD = 3V3.
--  Card setup (on a Linux host):
--     mkfs.ext4 /dev/sdX1  (or ext2/3); then put a file at /hello.txt
--  Note: writes need a NON-metadata_csum filesystem; reading default mkfs.ext4
--  works.  The SD block driver itself is not yet on-card-verified (see its
--  README), so bring that up first.
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
   procedure Banner;  pragma Import (C, Banner, "native_ext4_banner");
   procedure Card_R (Status : int);  pragma Import (C, Card_R, "native_ext4_card");
   procedure Mount_R (Ok, BS : int); pragma Import (C, Mount_R, "native_ext4_mount");
   procedure Read_R (Ok, B0, B1, B2, B3 : int);
   pragma Import (C, Read_R, "native_ext4_read");
   procedure Done;    pragma Import (C, Done, "native_ext4_done");

   use type ESP32S3.SD_SPI.Status;

   C  : aliased ESP32S3.SD_SPI.Card;
   St : ESP32S3.SD_SPI.Status;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   ESP32S3.SD_SPI.Setup
     (C, Host => ESP32S3.SPI.SPI2, Sclk => 12, Mosi => 11, Miso => 13, Cs => 10);
   ESP32S3.SD_SPI.Initialize (C, St);
   Card_R (if St = ESP32S3.SD_SPI.OK then 0 else 1);

   if St = ESP32S3.SD_SPI.OK then
      declare
         Dev : constant ESP32S3.Block_Dev.Device :=
                 ESP32S3.Block_Dev.SD_SPI_Source.Make (C'Access);
         M   : ESP32S3.Ext4.FS.Mount;
      begin
         M.Open (Dev, Read_Only => True);
         Mount_R (1, int (M.Block_Size));

         declare
            I    : ESP32S3.Ext4.Inode.Info;
            Buf  : Byte_Array (0 .. 15);
            Last : Natural;
         begin
            M.Stat (M.Lookup ("/hello.txt"), I);
            M.Read_File (I, 0, Buf, Last);
            Read_R (1, int (Buf (0)), int (Buf (1)), int (Buf (2)), int (Buf (3)));
         exception
            when others =>
               Read_R (0, 0, 0, 0, 0);
         end;
      exception
         when others =>
            Mount_R (0, 0);
      end;
   end if;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
