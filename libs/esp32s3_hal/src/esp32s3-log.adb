with System;
with Interfaces;        use Interfaces;
with Interfaces.C;

package body ESP32S3.Log is

   --  Fixed-signature ROM-printf wrappers (examples/common/bare/bare_log.c).
   procedure C_Cstr (S : System.Address);
   pragma Import (C, C_Cstr, "hal_log_cstr");

   procedure C_Uint (N : Interfaces.C.unsigned);
   pragma Import (C, C_Uint, "hal_log_uint");

   ---------
   -- Put --
   ---------

   procedure Put (S : String) is
      --  Copy into a stack buffer and NUL-terminate for C ("%s").
      Buf : String (1 .. S'Length + 1);
   begin
      if S'Length > 0 then
         Buf (1 .. S'Length) := S;
      end if;
      Buf (Buf'Last) := ASCII.NUL;
      C_Cstr (Buf'Address);
   end Put;

   procedure Put (C : Character) is
      Buf : aliased constant String := (1 => C, 2 => ASCII.NUL);
   begin
      C_Cstr (Buf'Address);
   end Put;

   --------------
   -- New_Line --
   --------------

   procedure New_Line is
      NL : aliased constant String := (ASCII.LF, ASCII.NUL);
   begin
      C_Cstr (NL'Address);
   end New_Line;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (S : String := "") is
   begin
      Put (S);
      New_Line;
   end Put_Line;

   ---------
   -- Put --
   ---------

   procedure Put (N : Integer; Width : Natural := 0; Pad : Character := ' ') is
      Digits_Buf : String (1 .. 11);            --  up to 10 digits
      D_First    : Natural := Digits_Buf'Last + 1;
      Neg        : constant Boolean := N < 0;
      U          : Long_Long_Integer := Long_Long_Integer (N);
   begin
      if Neg then
         U := -U;                                --  in 64-bit: safe for Integer'First
      end if;
      loop                                       --  digits, least-significant first
         D_First := D_First - 1;
         Digits_Buf (D_First) :=
           Character'Val (Character'Pos ('0') + Integer (U mod 10));
         U := U / 10;
         exit when U = 0;
      end loop;

      declare
         Digs     : constant String  := Digits_Buf (D_First .. Digits_Buf'Last);
         Sign_Len : constant Natural := (if Neg then 1 else 0);
         Body_Len : constant Natural := Sign_Len + Digs'Length;
         Pad_Len  : constant Natural :=
           (if Width > Body_Len then Width - Body_Len else 0);
         Out_Buf  : String (1 .. Body_Len + Pad_Len + 1);
         P        : Natural := 0;
      begin
         if Pad = '0' then
            if Neg then P := P + 1; Out_Buf (P) := '-'; end if;
            for I in 1 .. Pad_Len loop P := P + 1; Out_Buf (P) := '0'; end loop;
         else
            for I in 1 .. Pad_Len loop P := P + 1; Out_Buf (P) := Pad; end loop;
            if Neg then P := P + 1; Out_Buf (P) := '-'; end if;
         end if;
         Out_Buf (P + 1 .. P + Digs'Length) := Digs;
         P := P + Digs'Length;
         Out_Buf (P + 1) := ASCII.NUL;
         C_Cstr (Out_Buf'Address);
      end;
   end Put;

   ------------------
   -- Put_Unsigned --
   ------------------

   procedure Put_Unsigned (N : Interfaces.Unsigned_32) is
   begin
      C_Uint (Interfaces.C.unsigned (N));
   end Put_Unsigned;

   -------------
   -- Put_Hex --
   -------------

   procedure Put_Hex (N : Interfaces.Unsigned_32; Width : Natural := 0) is
      Hex        : constant array (0 .. 15) of Character := "0123456789abcdef";
      Digits_Buf : String (1 .. 8);
      D_First    : Natural := Digits_Buf'Last + 1;
      V          : Unsigned_32 := N;
   begin
      loop
         D_First := D_First - 1;
         Digits_Buf (D_First) := Hex (Integer (V and 16#F#));
         V := Shift_Right (V, 4);
         exit when V = 0;
      end loop;

      declare
         Digs    : constant String  := Digits_Buf (D_First .. Digits_Buf'Last);
         Pad_Len : constant Natural :=
           (if Width > Digs'Length then Width - Digs'Length else 0);
         Out_Buf : String (1 .. Digs'Length + Pad_Len + 1);
      begin
         for I in 1 .. Pad_Len loop
            Out_Buf (I) := '0';
         end loop;
         Out_Buf (Pad_Len + 1 .. Pad_Len + Digs'Length) := Digs;
         Out_Buf (Out_Buf'Last) := ASCII.NUL;
         C_Cstr (Out_Buf'Address);
      end;
   end Put_Hex;

   ---------------
   -- Put_Fixed --
   ---------------

   procedure Put_Fixed (Numer : Integer; Denom : Positive; Decimals : Natural := 2)
   is
      Neg   : constant Boolean           := Numer < 0;
      M     : constant Long_Long_Integer := abs (Long_Long_Integer (Numer));
      D     : constant Long_Long_Integer := Long_Long_Integer (Denom);
      Whole : constant Long_Long_Integer := M / D;
      Rem_M : constant Long_Long_Integer := M mod D;
      Scale : Long_Long_Integer := 1;
   begin
      for I in 1 .. Decimals loop
         Scale := Scale * 10;
      end loop;
      if Neg then
         Put ("-");
      end if;
      Put (Integer (Whole));
      if Decimals > 0 then
         Put (".");
         Put (Integer ((Rem_M * Scale) / D), Width => Decimals, Pad => '0');
      end if;
   end Put_Fixed;

end ESP32S3.Log;
