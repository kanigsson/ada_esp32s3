--  Mount a real ext4 (or ext2/3) SD card with the pure-Ada filesystem
--  (ESP32S3.Ext4) over the SDMMC block driver, on a board where the card's
--  DAT3/CD line is driven by a CH422G expander (IO4).  READ-ONLY: it lists the
--  root directory and reads /hello.txt; it never writes.
--
--  Wiring:  SDMMC 1-bit  CLK=IO12 CMD=IO11 D0=IO13 ; DAT3 via CH422G (I2C0
--  SDA=IO8 SCL=IO9, IO4).  The card must be formatted ext4 WHOLE-DEVICE
--  (mkfs.ext4 -F /dev/sdX, not a partition) so the superblock is at LBA 2.
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

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package CH renames ESP32S3.CH422G;
   package SD renames ESP32S3.SDMMC;
   use type CH.Status;
   use type SD.Status;

   procedure Banner;  pragma Import (C, Banner, "native_fs_banner");
   procedure Card_R (Ok : int);  pragma Import (C, Card_R, "native_fs_card");
   procedure Mount_R (Ok, BS : int);  pragma Import (C, Mount_R, "native_fs_mount");
   procedure Entry_R (Name : System.Address; Ino, Ftype : int);
                      pragma Import (C, Entry_R, "native_fs_entry");
   procedure File_R (Ok, Size : int; Preview : System.Address);
                      pragma Import (C, File_R, "native_fs_file");
   procedure Err_R (Stage : System.Address);  pragma Import (C, Err_R, "native_fs_err");
   procedure Done;  pragma Import (C, Done, "native_fs_done");

   Dev_CH : CH.Device;
   ExS    : CH.Session;
   ESt    : CH.Status;
   SDC    : aliased SD.Card;
   St     : SD.Status;

   --  NUL-terminate Str for the C %s glue, replacing non-printables with '.'.
   function Cstr (Str : String) return String is
      R : String (1 .. Str'Length + 1);
   begin
      for I in 1 .. Str'Length loop
         declare
            Ch : constant Character := Str (Str'First + I - 1);
         begin
            R (I) := (if Character'Pos (Ch) in 32 .. 126 then Ch else '.');
         end;
      end loop;
      R (R'Last) := Character'Val (0);
      return R;
   end Cstr;

   Empty : aliased constant String := (1 => Character'Val (0));

   procedure Visit (Name : String; Ino : Inode_Number; File_Type : U8) is
      N : aliased constant String := Cstr (Name);
   begin
      Entry_R (N'Address, int (Ino), int (File_Type));
   end Visit;

   procedure Stage (Name : String) is
      N : aliased constant String := Cstr (Name);
   begin
      Err_R (N'Address);
   end Stage;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  CH422G: drive DAT3/CD (IO4) high -- load the output register, then enable.
   CH.Setup (Dev_CH, Sda => 8, Scl => 9);
   CH.Acquire (ExS, Dev_CH);
   CH.Write_IO (ExS, 16#10#, ESt);
   if ESt = CH.OK then
      CH.Configure (ExS, IO_Dir => CH.Outputs, OC_Mode => CH.Push_Pull,
                    Result => ESt);
   end if;

   --  SDMMC: 1-bit, High Speed (50 MHz) if the card supports it.
   SD.Setup (SDC, On => SD.Slot1, Clk => 12, Cmd => 11, D0 => 13,
             Width => SD.Width_1, Data_Clock_Hz => 50_000_000,
             High_Speed => True);
   SD.Initialize (SDC, St);
   Card_R (Boolean'Pos (St = SD.OK));

   if St = SD.OK then
      declare
         BD : constant ESP32S3.Block_Dev.Device :=
                ESP32S3.Block_Dev.SDMMC_Source.Make (SDC'Access);
         M  : ESP32S3.Ext4.FS.Mount;
      begin
         M.Open (BD, Read_Only => True, Cache_Blocks => 16);
         Mount_R (1, int (M.Block_Size));

         --  List the root directory.
         declare
            RI : ESP32S3.Ext4.Inode.Info;
         begin
            M.Stat (M.Lookup ("/"), RI);
            M.Iterate (RI, Visit'Access);
         end;

         --  Read /hello.txt if present.
         declare
            I    : ESP32S3.Ext4.Inode.Info;
            Buf  : Byte_Array (0 .. 95);
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
