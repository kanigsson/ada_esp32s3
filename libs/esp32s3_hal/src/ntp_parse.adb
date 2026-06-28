with Ada.Streams; use Ada.Streams;
with Interfaces;  use Interfaces;

package body NTP_Parse with SPARK_Mode => On is

   procedure Parse_Timestamp
     (Resp      : Ada.Streams.Stream_Element_Array;
      Last      : Ada.Streams.Stream_Element_Offset;
      Unix_Time : out Interfaces.Integer_64;
      Ok        : out Boolean)
   is
      Base : constant Stream_Element_Offset := Resp'First;  --  datagram start
      Secs : Unsigned_32;
   begin
      Unix_Time := 0;
      Ok        := False;

      --  The transmit timestamp's seconds occupy bytes 40..43; the reply must be
      --  long enough to hold byte 43.
      if Last < Base + 43 then
         return;
      end if;

      Secs := Shift_Left (Unsigned_32 (Resp (Base + 40)), 24)
           or Shift_Left (Unsigned_32 (Resp (Base + 41)), 16)
           or Shift_Left (Unsigned_32 (Resp (Base + 42)),  8)
           or            Unsigned_32 (Resp (Base + 43));

      if Secs = 0 then                  --  unsynchronised / kiss-o'-death
         return;
      end if;

      --  Secs is in 0 .. 2**32-1, so Integer_64 (Secs) - NTP_Unix lands in
      --  -2_208_988_800 .. 2_085_978_495 (years 1900..2036) -- no overflow.
      Unix_Time := Integer_64 (Secs) - NTP_Unix;
      Ok        := True;
   end Parse_Timestamp;

   procedure To_UTC
     (Unix_Time : Interfaces.Integer_64;
      Year      : out Integer;
      Month     : out Integer;
      Day       : out Integer;
      Hour      : out Integer;
      Minute    : out Integer;
      Second    : out Integer)
   is
      D_Days : constant Integer_64 := Unix_Time / 86_400;
      Sod    : constant Integer_64 := Unix_Time mod 86_400;
      Z      : constant Integer_64 := D_Days + 719_468;
      Era    : constant Integer_64 := Z / 146_097;
      DOE    : constant Integer_64 := Z - Era * 146_097;
      YOE    : constant Integer_64 :=
        (DOE - DOE / 1460 + DOE / 36524 - DOE / 146096) / 365;
      Yr     : constant Integer_64 := YOE + Era * 400;
      DOY    : constant Integer_64 := DOE - (365 * YOE + YOE / 4 - YOE / 100);
      MP     : constant Integer_64 := (5 * DOY + 2) / 153;
   begin
      Day    := Integer (DOY - (153 * MP + 2) / 5 + 1);
      Month  := Integer (if MP < 10 then MP + 3 else MP - 9);
      Year   := Integer (if Month <= 2 then Yr + 1 else Yr);
      Hour   := Integer (Sod / 3600);
      Minute := Integer ((Sod mod 3600) / 60);
      Second := Integer (Sod mod 60);
   end To_UTC;

end NTP_Parse;
