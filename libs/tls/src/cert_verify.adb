with ESP32S3.RSA;
with SPARKNaCl;
with SPARKNaCl.Hashing.SHA256;

package body Cert_Verify is

   use type X509.U8;
   subtype U8 is X509.U8;
   subtype Byte_Array is X509.Byte_Array;

   --  DigestInfo prefix for SHA-256 (the DER of the algorithm + the OCTET STRING
   --  header that precedes the 32-byte hash in a PKCS#1 v1.5 block).
   DI_Prefix : constant Byte_Array (0 .. 18) :=
     (16#30#, 16#31#, 16#30#, 16#0D#, 16#06#, 16#09#, 16#60#, 16#86#, 16#48#,
      16#01#, 16#65#, 16#03#, 16#04#, 16#02#, 16#01#, 16#05#, 16#00#, 16#04#,
      16#20#);

   --  Big-endian bytes -> little-endian 32-bit words (word 0 least significant).
   --  W may hold more words than B fills; the high words are zeroed.
   procedure BE_To_Words (B : Byte_Array; W : out ESP32S3.RSA.Word_Array) is
      use ESP32S3.RSA;
   begin
      for J in 0 .. W'Length - 1 loop
         declare
            P   : constant Integer := Integer (B'Last) - 4 * J;   --  LSB of word J
            Acc : Word := 0;
         begin
            if P     >= Integer (B'First) then Acc := Acc + Word (B (P)); end if;
            if P - 1 >= Integer (B'First) then Acc := Acc + Word (B (P - 1)) * 16#100#; end if;
            if P - 2 >= Integer (B'First) then Acc := Acc + Word (B (P - 2)) * 16#1_0000#; end if;
            if P - 3 >= Integer (B'First) then Acc := Acc + Word (B (P - 3)) * 16#100_0000#; end if;
            W (W'First + J) := Acc;
         end;
      end loop;
   end BE_To_Words;

   --  Little-endian words -> big-endian bytes (EM'Length must be 4 * W'Length).
   procedure Words_To_BE (W : ESP32S3.RSA.Word_Array; EM : out Byte_Array) is
      use ESP32S3.RSA;
   begin
      for J in 0 .. W'Length - 1 loop
         declare
            Wd : constant Word    := W (W'First + J);
            P  : constant Natural := EM'Last - 4 * J;             --  LSB of word J
         begin
            EM (P)     := U8 (Wd mod 16#100#);
            EM (P - 1) := U8 ((Wd / 16#100#)     mod 16#100#);
            EM (P - 2) := U8 ((Wd / 16#1_0000#)  mod 16#100#);
            EM (P - 3) := U8 ((Wd / 16#100_0000#) mod 16#100#);
         end;
      end loop;
   end Words_To_BE;

   function RSA_PKCS1_SHA256 (TBS, Signature, Modulus, Exponent : Byte_Array)
      return Boolean
   is
      M_First : Natural := Modulus'First;
   begin
      --  Drop a single leading 0x00 (DER positive-sign byte) from the modulus.
      if Modulus'Length >= 1 and then Modulus (Modulus'First) = 0 then
         M_First := Modulus'First + 1;
      end if;

      declare
         K : constant Natural :=
           (if Modulus'Last >= M_First then Modulus'Last - M_First + 1 else 0);
      begin
         --  k must be a whole number of words, RSA-sized, and big enough for the
         --  block (00 01 || >=8 * FF || 00 || 19-byte DigestInfo || 32-byte hash).
         if K = 0 or else K mod 4 /= 0 or else K > 512
           or else K < 62 or else Signature'Length /= K
         then
            return False;
         end if;

         declare
            use ESP32S3.RSA;
            N             : constant Natural := K / 4;
            Nm, Sg, Ex, Z : Word_Array (0 .. N - 1);
            Ok            : Boolean;
            EM, Want      : Byte_Array (0 .. K - 1);
            PS_Len        : constant Natural := K - 3 - (DI_Prefix'Length + 32);
            Dg            : SPARKNaCl.Hashing.SHA256.Digest;
            Diff          : U8 := 0;
            Pos           : Natural;
         begin
            BE_To_Words (Modulus (M_First .. Modulus'Last), Nm);
            BE_To_Words (Signature, Sg);
            BE_To_Words (Exponent, Ex);

            --  Recover the padded block: EM = Signature^Exponent mod Modulus.
            Mod_Exp (Sg, Ex, Nm, Z, Ok);
            if not Ok then
               return False;
            end if;
            Words_To_BE (Z, EM);

            --  SHA-256 of the signed region (TBS).
            declare
               Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (TBS'Length - 1));
            begin
               for I in 0 .. TBS'Length - 1 loop
                  Msg (SPARKNaCl.N32 (I)) := SPARKNaCl.Byte (TBS (TBS'First + I));
               end loop;
               Dg := SPARKNaCl.Hashing.SHA256.Hash (Msg);
            end;

            --  Build the expected block: 00 01 FF..FF 00 || DigestInfo || hash.
            Want (0) := 16#00#;
            Want (1) := 16#01#;
            Pos := 2;
            for I in 0 .. PS_Len - 1 loop
               Want (Pos + I) := 16#FF#;
            end loop;
            Pos := Pos + PS_Len;
            Want (Pos) := 16#00#;
            Pos := Pos + 1;
            for I in DI_Prefix'Range loop
               Want (Pos) := DI_Prefix (I);
               Pos := Pos + 1;
            end loop;
            for I in 0 .. 31 loop
               Want (Pos) := U8 (Dg (SPARKNaCl.N32 (I)));
               Pos := Pos + 1;
            end loop;

            --  Constant-time compare.
            for I in EM'Range loop
               Diff := Diff or (EM (I) xor Want (I));
            end loop;
            return Diff = 0;
         end;
      end;
   end RSA_PKCS1_SHA256;

end Cert_Verify;
