with ESP32S3_Registers;            use ESP32S3_Registers;
with ESP32S3_Registers.RSA;
with ESP32S3_Registers.SYSTEM;

package body ESP32S3.RSA is

   package R   renames ESP32S3_Registers.RSA;
   package Sys renames ESP32S3_Registers.SYSTEM;

   Spin_Limit : constant := 100_000_000;   --  ~1-2 s at 240 MHz; modexp takes ms

   --  -M^-1 mod 2^32 from the low word of M (Newton's iteration; M is odd, so M0
   --  is odd and invertible mod 2^32).  Inv := M0 is correct to 3 bits; each step
   --  doubles the correct bits (3 -> 6 -> 12 -> 24 -> 48 > 32).
   function M_Prime (M0 : Word) return Word is
      Inv : Word := M0;
   begin
      for K in 1 .. 4 loop
         Inv := Inv * (2 - M0 * Inv);
      end loop;
      return (not Inv) + 1;            --  negate mod 2^32
   end M_Prime;

   --  Power up the accelerator and wait for its memory to initialise.
   function Enable return Boolean is
   begin
      Sys.SYSTEM_Periph.PERIP_CLK_EN1.CRYPTO_RSA_CLK_EN := True;
      Sys.SYSTEM_Periph.PERIP_RST_EN1.CRYPTO_RSA_RST    := False;  --  release reset
      Sys.SYSTEM_Periph.RSA_PD_CTRL.RSA_MEM_PD          := False;  --  power up memory
      for K in 1 .. Spin_Limit loop
         if R.RSA_Periph.CLEAN.CLEAN then       --  1 = memories initialised
            return True;
         end if;
      end loop;
      return False;
   end Enable;

   procedure Disable is
   begin
      Sys.SYSTEM_Periph.PERIP_CLK_EN1.CRYPTO_RSA_CLK_EN := False;
   end Disable;

   procedure Mod_Exp (X, Y, M, R2 : Word_Array;
                      Z  : out Word_Array;
                      Ok : out Boolean)
   is
      N    : constant Natural := M'Length;
      Done : Boolean := False;
   begin
      Z  := (others => 0);
      Ok := False;
      if not Enable then
         return;
      end if;

      R.RSA_Periph.MODE.MODE := R.MODE_MODE_Field (N - 1);     --  N words
      for I in 0 .. N - 1 loop                                 --  load operands
         R.RSA_Periph.X_MEM (I) := UInt32 (X  (X'First  + I));
         R.RSA_Periph.Y_MEM (I) := UInt32 (Y  (Y'First  + I));
         R.RSA_Periph.M_MEM (I) := UInt32 (M  (M'First  + I));
         R.RSA_Periph.Z_MEM (I) := UInt32 (R2 (R2'First + I)); --  R^2 mod M
      end loop;
      R.RSA_Periph.M_PRIME := UInt32 (M_Prime (M (M'First)));

      R.RSA_Periph.CONSTANT_TIME.CONSTANT_TIME := True;        --  timing-attack guard
      R.RSA_Periph.SEARCH_ENABLE.SEARCH_ENABLE := False;
      R.RSA_Periph.MODEXP_START.MODEXP_START   := True;

      for K in 1 .. Spin_Limit loop
         if R.RSA_Periph.IDLE.IDLE then        --  1 = accelerator idle (done)
            Done := True;
            exit;
         end if;
      end loop;
      R.RSA_Periph.CLEAR_INTERRUPT.CLEAR_INTERRUPT := True;

      if Done then
         for I in 0 .. N - 1 loop
            Z (Z'First + I) := Word (R.RSA_Periph.Z_MEM (I));
         end loop;
         Ok := True;
      end if;
      Disable;
   end Mod_Exp;

end ESP32S3.RSA;
