with Ada.Unchecked_Conversion;
with Interfaces; use Interfaces;

package body Glyph_Fonts is

   package LCD renames ESP32S3.ST7789;

   --  Fixed-size views overlaid on the imported atlas arrays (we only ever index
   --  valid spans: metrics < Count <= 256, offsets/bytes within the real data).
   type U8_View  is array (Natural range 0 .. 262_143) of Unsigned_8;
   type I8_View  is array (Natural range 0 .. 1_023)   of Integer_8;
   type U16_View is array (Natural range 0 .. 1_023)   of Unsigned_16;
   type U8_Ptr  is access all U8_View;
   type I8_Ptr  is access all I8_View;
   type U16_Ptr is access all U16_View;
   function To_U8  is new Ada.Unchecked_Conversion (System.Address, U8_Ptr);
   function To_I8  is new Ada.Unchecked_Conversion (System.Address, I8_Ptr);
   function To_U16 is new Ada.Unchecked_Conversion (System.Address, U16_Ptr);

   ----------------
   -- Text_Width --
   ----------------

   function Text_Width (F : Font; Str : String) return Natural is
      Adv : constant U8_Ptr := To_U8 (F.Adv);
      W   : Natural := 0;
   begin
      for Ch of Str loop
         declare
            Code : constant Integer := Character'Pos (Ch);
         begin
            if Code in F.First .. F.First + F.Count - 1 then
               W := W + Natural (Adv (Code - F.First));
            end if;
         end;
      end loop;
      return W;
   end Text_Width;

   ---------------
   -- Draw_Text --
   ---------------

   procedure Draw_Text
     (S        : ESP32S3.ST7789.Session;
      F        : Font;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      FG, BG   : ESP32S3.ST7789.Color)
   is
      Adv  : constant U8_Ptr  := To_U8 (F.Adv);
      GW   : constant U8_Ptr  := To_U8 (F.W);
      GH   : constant U8_Ptr  := To_U8 (F.H);
      XOff : constant I8_Ptr  := To_I8 (F.XOff);
      YOff : constant I8_Ptr  := To_I8 (F.YOff);
      GOff : constant U16_Ptr := To_U16 (F.Off);
      Bits : constant U8_Ptr  := To_U8 (F.Bits);

      --  16-step BG->FG colour ramp (channel-wise via RGB565), built once.
      type Ramp16 is array (0 .. 15) of LCD.Color;
      function Make_Ramp return Ramp16 is
         BGI  : constant Natural := Natural (BG);
         FGI  : constant Natural := Natural (FG);
         Bk_R : constant Natural := (BGI / 2048) mod 32 * 255 / 31;
         Bk_G : constant Natural := (BGI / 32)   mod 64 * 255 / 63;
         Bk_B : constant Natural := (BGI mod 32) * 255 / 31;
         Ft_R : constant Natural := (FGI / 2048) mod 32 * 255 / 31;
         Ft_G : constant Natural := (FGI / 32)   mod 64 * 255 / 63;
         Ft_B : constant Natural := (FGI mod 32) * 255 / 31;
         R    : Ramp16;
      begin
         for K in Ramp16'Range loop
            R (K) := LCD.RGB (Bk_R + (Ft_R - Bk_R) * K / 15,
                              Bk_G + (Ft_G - Bk_G) * K / 15,
                              Bk_B + (Ft_B - Bk_B) * K / 15);
         end loop;
         return R;
      end Make_Ramp;

      Ramp : constant Ramp16 := Make_Ramp;
      Pen  : Integer := X;

      procedure Draw_Glyph (G : Natural) is
         W   : constant Natural := Natural (GW (G));
         H   : constant Natural := Natural (GH (G));
         Off : constant Natural := Natural (GOff (G));
      begin
         if W = 0 or else H = 0 then
            return;
         end if;
         declare
            Cell : LCD.Color_Array (0 .. W * H - 1);
            Nib  : Natural;
            Byte : Unsigned_8;
         begin
            for I in Cell'Range loop          --  4-bit coverage, 2 px/byte
               Byte := Bits (Off + I / 2);
               Nib  := (if I mod 2 = 0
                        then Natural (Byte) / 16 else Natural (Byte) mod 16);
               Cell (I) := Ramp (Nib);
            end loop;
            LCD.Draw_Bitmap (S, Pen + Integer (XOff (G)),
                             Baseline + Integer (YOff (G)), W, H, Cell);
         end;
      end Draw_Glyph;

   begin
      for Ch of Str loop
         declare
            Code : constant Integer := Character'Pos (Ch);
         begin
            if Code in F.First .. F.First + F.Count - 1 then
               Draw_Glyph (Code - F.First);
               Pen := Pen + Integer (Adv (Code - F.First));
            end if;
         end;
      end loop;
   end Draw_Text;

end Glyph_Fonts;
