--  What: mount a real ext4 (or ext2/3) SD card with the pure-Ada filesystem
--  (ESP32S3.Ext4) over the SDMMC block driver, then list the root directory and
--  read /hello.txt.  READ-ONLY -- it never writes.  This is the first on-card
--  bring-up of the pure-Ada ext4 FS (previously only host-verified vs e2fsck).
--
--  Build & run:  ./x run esp32s3_ext4_sdmmc
--    Needs the embedded (or full) profile, NOT the default light-tasking: the FS
--    and SDMMC use controlled types + the secondary stack.  build.sh sets
--    ESP32S3_RTS_PROFILE=embedded and a 256 KB heap for the FS block cache.
--
--  Output (each line prefixed "[ext4] "):
--    SD init: OK                       -- card detected and initialised
--    mount: OK   block size = 4096     -- ext4 superblock parsed (4 KB blocks)
--    one line per root-directory entry -- "<type> ino=<n>  <name>"
--    /hello.txt: <n> bytes = "<text>"  -- file contents preview
--    done.
--  A FAILED on SD init / mount, or an "ERROR:" line, means the card is missing
--  or not formatted ext4 whole-device (see Hardware below).
--
--  Hardware:  an SD card formatted ext4 over the WHOLE DEVICE (mkfs.ext4 -F
--  /dev/sdX, NOT a partition) so the superblock lands at the standard LBA 2.
--  SDMMC is wired 1-bit: CLK=IO12, CMD=IO11, D0=IO13.  On this board the card's
--  DAT3/CD line is not on a GPIO but on a CH422G I2C expander (IO4), so it is
--  held high over I2C0 (SDA=IO8, SCL=IO9) before the card is initialised.
with System;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.CH422G;
with ESP32S3.SDMMC;
with ESP32S3.Block_Dev;
with ESP32S3.Block_Dev.SDMMC_Source;
with ESP32S3.Ext4;       use ESP32S3.Ext4;
with ESP32S3.Ext4.FS;
with ESP32S3.Ext4.Inode;
with FS_Glue;            use FS_Glue;   --  library-level glue (closure-free cb)

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package CH renames ESP32S3.CH422G;
   package SD renames ESP32S3.SDMMC;
   use type CH.Status;
   use type SD.Status;

   --  Console glue (Banner/Card_R/Mount_R/Entry_R/File_R/Err_R/Done) and Cstr
   --  live in the library-level package FS_Glue so the Iterate callback below
   --  stays closure-free (no GNAT stack trampoline -- see FS_Glue).

   --  CH422G I2C expander pins (this board): the SD DAT3/CD line is on IO4.
   CH422G_Sda_Pin : constant := 8;       --  I2C0 SDA
   CH422G_Scl_Pin : constant := 9;       --  I2C0 SCL

   --  Output-register value that drives the expander's IO4 high.  IO4 is bit 4,
   --  so 2**4 = 16#10#; this holds the card's DAT3/CD asserted (card present).
   CH422G_IO4_High : constant := 16#10#;

   --  SDMMC slot-1 wiring (1-bit bus) and clock.
   SDMMC_Clk_Pin    : constant := 12;
   SDMMC_Cmd_Pin    : constant := 11;
   SDMMC_D0_Pin     : constant := 13;
   SDMMC_Clock_Hz   : constant := 50_000_000;   --  High Speed: 50 MHz

   --  ext4 block cache: 16 blocks (16 x 4 KB) on the heap build.sh sized.
   FS_Cache_Blocks : constant := 16;

   Dev_CH : CH.Device;
   ExS    : CH.Session;
   ESt    : CH.Status;
   SDC    : aliased SD.Card;
   St     : SD.Status;

   Empty : aliased constant String := (1 => Character'Val (0));

   --  Let the USB-serial console attach before the first line is printed.
   Startup_Delay : constant Time_Span := Milliseconds (200);

   procedure Stage (Name : String) is
      N : aliased constant String := Cstr (Name);
   begin
      Err_R (N'Address);
   end Stage;
begin
   delay until Clock + Startup_Delay;
   Banner;

   --  CH422G: drive DAT3/CD (IO4) high -- load the output register, then enable
   --  the pins as push-pull outputs.  Order matters: set the value first so the
   --  line is already high the instant the pins switch to drive.
   CH.Setup (Dev_CH, Sda => CH422G_Sda_Pin, Scl => CH422G_Scl_Pin);
   CH.Acquire (ExS, Dev_CH);
   CH.Write_IO (ExS, CH422G_IO4_High, ESt);
   if ESt = CH.OK then
      CH.Configure (ExS, IO_Dir => CH.Outputs, OC_Mode => CH.Push_Pull,
                    Result => ESt);
   end if;

   --  SDMMC: 1-bit, High Speed (50 MHz) if the card supports it.
   SD.Setup (SDC, On => SD.Slot1,
             Clk => SDMMC_Clk_Pin, Cmd => SDMMC_Cmd_Pin, D0 => SDMMC_D0_Pin,
             Width => SD.Width_1, Data_Clock_Hz => SDMMC_Clock_Hz,
             High_Speed => True);
   SD.Initialize (SDC, St);
   Card_R (Boolean'Pos (St = SD.OK));

   if St = SD.OK then
      declare
         BD : constant ESP32S3.Block_Dev.Device :=
                ESP32S3.Block_Dev.SDMMC_Source.Make (SDC'Access);
         M  : ESP32S3.Ext4.FS.Mount;
      begin
         M.Open (BD, Read_Only => True, Cache_Blocks => FS_Cache_Blocks);
         Mount_R (1, int (M.Block_Size));

         --  List the root directory.
         declare
            RI : ESP32S3.Ext4.Inode.Info;
         begin
            M.Stat (M.Lookup ("/"), RI);
            M.Iterate (RI, Visit'Access);
         end;

         --  Read the start of /hello.txt (if present) for the console preview.
         declare
            --  Read at most this many bytes -- enough to preview the file.
            Preview_Bytes : constant := 96;

            I    : ESP32S3.Ext4.Inode.Info;
            Buf  : Byte_Array (0 .. Preview_Bytes - 1);
            Last : Natural;
         begin
            M.Stat (M.Lookup ("/hello.txt"), I);
            M.Read_File (I, 0, Buf, Last);
            declare
               Text : String (1 .. Last);
            begin
               for K in 0 .. Last - 1 loop
                  Text (K + 1) := Character'Val (Buf (K));
               end loop;
               declare
                  P : aliased constant String := Cstr (Text);
               begin
                  File_R (1, int (Last), P'Address);
               end;
            end;
         exception
            when others =>
               File_R (0, 0, Empty'Address);
         end;
      exception
         when others =>
            Stage ("mount / list (is the card formatted ext4 whole-device?)");
      end;
   end if;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
