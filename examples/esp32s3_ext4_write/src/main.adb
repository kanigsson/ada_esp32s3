--  ext4 WRITE test for the pure-Ada filesystem (ESP32S3.Ext4) over SDMMC, on a
--  board where the SD card's DAT3/CD is driven by a CH422G expander (IO4).
--
--  It mounts read-write, creates /ada_write.txt, writes a known string, commits
--  it as a journaled transaction, then reads it back and verifies byte-for-byte.
--  The card can then be taken to a host: 'e2fsck -f' is clean and the file is
--  readable (the FS's writes are validated against e2fsck in the host harness).
--
--  The card MUST be formatted NON-metadata_csum and whole-device:
--     mkfs.ext4 -F -O ^metadata_csum /dev/sdX
--  Writing to a metadata_csum filesystem is refused (Read_Only) so the FS never
--  leaves stale checksums a host would flag -- the test reports that case.
--
--  Wiring:  SDMMC 1-bit CLK=IO12 CMD=IO11 D0=IO13 ; DAT3 via CH422G (I2C0
--  SDA=IO8 SCL=IO9, IO4).
with System;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Exceptions; use Ada.Exceptions;

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

   procedure Banner;  pragma Import (C, Banner, "native_w_banner");
   procedure Card_R (Ok : int);   pragma Import (C, Card_R, "native_w_card");
   procedure Mount_R (Ok : int);  pragma Import (C, Mount_R, "native_w_mount");
   procedure Write_R (Ok : int; Msg : System.Address);
                      pragma Import (C, Write_R, "native_w_write");
   procedure Verify_R (Ok, Size : int; Content : System.Address);
                      pragma Import (C, Verify_R, "native_w_verify");
   procedure Step_C (S : System.Address);  pragma Import (C, Step_C, "native_w_step");
   procedure Done;  pragma Import (C, Done, "native_w_done");

   Dev_CH : CH.Device;
   ExS    : CH.Session;
   ESt    : CH.Status;
   SDC    : aliased SD.Card;
   St     : SD.Status;

   File_Name : constant String := "ada_write.txt";
   Content   : constant String :=
     "Written by ESP32-S3 pure-Ada ext4 over SDMMC!" & ASCII.LF;

   --  NUL-terminate Str for the C %s glue (non-printables -> '.').
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

   procedure Report_Write_Error (Msg : String) is
      M : aliased constant String := Cstr (Msg);
   begin
      Write_R (0, M'Address);
   end Report_Write_Error;

   procedure Step (S : String) is
      M : aliased constant String := Cstr (S);
   begin
      Step_C (M'Address);
   end Step;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  CH422G: drive DAT3/CD (IO4) high.
   CH.Setup (Dev_CH, Sda => 8, Scl => 9);
   CH.Acquire (ExS, Dev_CH);
   CH.Write_IO (ExS, 16#10#, ESt);
   if ESt = CH.OK then
      CH.Configure (ExS, IO_Dir => CH.Outputs, OC_Mode => CH.Push_Pull,
                    Result => ESt);
   end if;

   --  SDMMC: 1-bit, High Speed.
   SD.Setup (SDC, On => SD.Slot1, Clk => 12, Cmd => 11, D0 => 13,
             Width => SD.Width_1, Data_Clock_Hz => 50_000_000,
             High_Speed => True);
   SD.Initialize (SDC, St);
   Card_R (Boolean'Pos (St = SD.OK));
   if St /= SD.OK then
      Done;
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   declare
      BD : constant ESP32S3.Block_Dev.Device :=
             ESP32S3.Block_Dev.SDMMC_Source.Make (SDC'Access);
      M  : ESP32S3.Ext4.FS.Mount;
   begin
      M.Open (BD, Read_Only => False, Cache_Blocks => 16);
      Mount_R (1);

      --  Build the content as bytes.
      declare
         Data : Byte_Array (0 .. Content'Length - 1);
         N    : Inode_Number;
      begin
         for K in Content'Range loop
            Data (K - Content'First) := Character'Pos (Content (K));
         end loop;

         --  Remove a leftover from a previous run, so the test is repeatable.
         Step ("unlink-if-present");
         begin
            M.Unlink ("/", File_Name);
            M.Commit;
         exception
            when Name_Error => null;        --  not there yet -- fine
         end;

         --  Create + write + commit (one journaled transaction).
         Step ("create_file");
         N := M.Create_File ("/", File_Name);
         Step ("write_file");
         M.Write_File (N, Data);
         Step ("commit");
         M.Commit;
         Step ("committed");
         Write_R (1, System.Null_Address);

         --  Read it back and verify byte-for-byte.
         declare
            I    : ESP32S3.Ext4.Inode.Info;
            Buf  : Byte_Array (0 .. 127);
            Last : Natural;
            Ok   : Boolean;
         begin
            M.Stat (M.Lookup ("/" & File_Name), I);
            M.Read_File (I, 0, Buf, Last);
            Ok := Last = Data'Length;
            if Ok then
               for K in 0 .. Last - 1 loop
                  Ok := Ok and then Buf (K) = Data (K);
               end loop;
            end if;
            declare
               Text : String (1 .. Last);
            begin
               for K in 0 .. Last - 1 loop
                  Text (K + 1) := Character'Val (Buf (K));
               end loop;
               declare
                  P : aliased constant String := Cstr (Text);
               begin
                  Verify_R (Boolean'Pos (Ok), int (Last), P'Address);
               end;
            end;
         end;
      end;
   exception
      when ESP32S3.Ext4.Read_Only =>
         Report_Write_Error
           ("metadata_csum volume -- reformat: mkfs.ext4 -O ^metadata_csum");
      when E : others =>
         Report_Write_Error (Exception_Name (E));
   end;

   Done;
   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
