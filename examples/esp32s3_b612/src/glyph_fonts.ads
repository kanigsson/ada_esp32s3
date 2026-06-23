with System;
with Interfaces;
with ESP32S3.ST7789;

--  Proportional anti-aliased bitmap-font text renderer for the ST7789, driving
--  the reusable display driver.  A Font is a light descriptor that POINTS (by
--  address) at flat glyph-atlas arrays generated offline (see main/gen_b612.py).
--  Coverage is 4-bit (2 px/byte); each glyph pixel is alpha-blended between BG
--  and FG (a 16-entry ramp built per call) -- so anti-aliasing works on the
--  write-only panel with no read-back.
--
--  Because each atlas size is a separate set of arrays (separate sections), a
--  program only spends flash on the Font values it actually references.
package Glyph_Fonts is

   --  Atlas array element types (the generated B612_Atlas imports these).
   type Byte_Array  is array (Natural range <>) of Interfaces.Unsigned_8;
   type SByte_Array is array (Natural range <>) of Interfaces.Integer_8;
   type U16_Array   is array (Natural range <>) of Interfaces.Unsigned_16;

   --  A font descriptor.  First/Count give the covered code range
   --  [First .. First+Count-1]; Ascent is the baseline offset from a line's top,
   --  Height the line advance.  The seven addresses point at the per-glyph metric
   --  arrays (adv, w, h, xoff, yoff, off) and the packed coverage bytes.
   type Font is record
      First, Count   : Natural;
      Height, Ascent : Natural;
      Adv, W, H      : System.Address;
      XOff, YOff     : System.Address;
      Off            : System.Address;     --  U16 byte-offset into Bits per glyph
      Bits           : System.Address;     --  4-bit coverage, 2 px/byte
   end record;

   --  Pixel advance of Str in font F (sum of glyph advances; unknown codes skip).
   function Text_Width (F : Font; Str : String) return Natural;

   --  Draw Str with its baseline left end at (X, Baseline), FG over a known BG.
   --  Caller holds the display Session (the two-level lock) and has painted BG.
   procedure Draw_Text
     (S        : ESP32S3.ST7789.Session;
      F        : Font;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      FG, BG   : ESP32S3.ST7789.Color);

end Glyph_Fonts;
