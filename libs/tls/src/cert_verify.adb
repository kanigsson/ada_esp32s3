with ESP32S3.RSA;
with SPARKNaCl;
with SPARKNaCl.Hashing.SHA256;
with SPARKNaCl.Hashing.SHA384;
with P256;

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

   ---------------------------------------------------------------------------
   --  RSASSA-PSS (MGF1-SHA-256, salt length 32)
   ---------------------------------------------------------------------------

   function SHA256_BA (Data : Byte_Array) return Byte_Array is
      Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Data'Length - 1));
      Dg  : SPARKNaCl.Hashing.SHA256.Digest;
      R   : Byte_Array (0 .. 31);
   begin
      for I in 0 .. Data'Length - 1 loop
         Msg (SPARKNaCl.N32 (I)) := SPARKNaCl.Byte (Data (Data'First + I));
      end loop;
      Dg := SPARKNaCl.Hashing.SHA256.Hash (Msg);
      for I in 0 .. 31 loop
         R (I) := U8 (Dg (SPARKNaCl.Index_32 (I)));
      end loop;
      return R;
   end SHA256_BA;

   --  MGF1 with SHA-256.
   function MGF1 (Seed : Byte_Array; Mask_Len : Natural) return Byte_Array is
      R   : Byte_Array (0 .. Mask_Len - 1);
      Pos : Natural := 0;
      Cnt : Natural := 0;
   begin
      while Pos < Mask_Len loop
         declare
            In_Buf : Byte_Array (0 .. Seed'Length + 3);
            H      : Byte_Array (0 .. 31);
         begin
            for I in 0 .. Seed'Length - 1 loop
               In_Buf (I) := Seed (Seed'First + I);
            end loop;
            In_Buf (Seed'Length)     := U8 ((Cnt / 16#100_0000#) mod 256);
            In_Buf (Seed'Length + 1) := U8 ((Cnt / 16#1_0000#) mod 256);
            In_Buf (Seed'Length + 2) := U8 ((Cnt / 16#100#) mod 256);
            In_Buf (Seed'Length + 3) := U8 (Cnt mod 256);
            H := SHA256_BA (In_Buf);
            for I in 0 .. 31 loop
               if Pos + I < Mask_Len then R (Pos + I) := H (I); end if;
            end loop;
            Pos := Pos + 32;
            Cnt := Cnt + 1;
         end;
      end loop;
      return R;
   end MGF1;

   function RSA_PSS_SHA256 (Message, Signature, Modulus, Exponent : Byte_Array)
      return Boolean
   is
      M_First : Natural := Modulus'First;
   begin
      if Modulus'Length >= 1 and then Modulus (Modulus'First) = 0 then
         M_First := Modulus'First + 1;
      end if;
      declare
         K : constant Natural :=
           (if Modulus'Last >= M_First then Modulus'Last - M_First + 1 else 0);
      begin
         if K = 0 or else K mod 4 /= 0 or else K > 512
           or else Signature'Length /= K
         then
            return False;
         end if;
         declare
            use ESP32S3.RSA;
            N             : constant Natural := K / 4;
            Nm, Sg, Ex, Z : Word_Array (0 .. N - 1);
            Ok            : Boolean;
            EMb           : Byte_Array (0 .. K - 1);
            hLen          : constant := 32;
            sLen          : constant := 32;
            Topb          : Natural := 0;
            Tt            : U8 := Modulus (M_First);
         begin
            BE_To_Words (Modulus (M_First .. Modulus'Last), Nm);
            BE_To_Words (Signature, Sg);
            BE_To_Words (Exponent, Ex);
            Mod_Exp (Sg, Ex, Nm, Z, Ok);          --  EM = sig^e mod n  (k bytes BE)
            if not Ok then
               return False;
            end if;
            Words_To_BE (Z, EMb);
            while Tt /= 0 loop Topb := Topb + 1; Tt := Tt / 2; end loop;
            declare
               ModBits  : constant Natural := (K - 1) * 8 + Topb;
               EmBits   : constant Natural := ModBits - 1;
               EmLen    : constant Natural := (EmBits + 7) / 8;
               LeadBits : constant Natural := 8 * EmLen - EmBits;
               EM_Off   : constant Natural := K - EmLen;
               DBLen    : constant Natural := EmLen - hLen - 1;
               ZeroN    : constant Natural := EmLen - hLen - sLen - 2;
               mHash    : constant Byte_Array := SHA256_BA (Message);
               H        : Byte_Array (0 .. hLen - 1);
            begin
               if EmLen < hLen + sLen + 2 or else EM_Off + EmLen /= K then
                  return False;
               end if;
               if EMb (EM_Off + EmLen - 1) /= 16#BC# then         --  trailer
                  return False;
               end if;
               if LeadBits > 0
                 and then (EMb (EM_Off) and U8 (16#100# - 2 ** (8 - LeadBits))) /= 0
               then
                  return False;
               end if;
               for I in 0 .. hLen - 1 loop
                  H (I) := EMb (EM_Off + DBLen + I);
               end loop;
               declare
                  DBMask : constant Byte_Array := MGF1 (H, DBLen);
                  DB     : Byte_Array (0 .. DBLen - 1);
                  Salt   : Byte_Array (0 .. sLen - 1);
                  Mp     : Byte_Array (0 .. 8 + hLen + sLen - 1) := (others => 0);
                  Hp     : Byte_Array (0 .. hLen - 1);
                  Good   : Boolean := True;
               begin
                  for I in 0 .. DBLen - 1 loop
                     DB (I) := EMb (EM_Off + I) xor DBMask (I);
                  end loop;
                  if LeadBits > 0 then
                     DB (0) := DB (0) and U8 (2 ** (8 - LeadBits) - 1);
                  end if;
                  for I in 0 .. ZeroN - 1 loop
                     if DB (I) /= 0 then Good := False; end if;
                  end loop;
                  if DB (ZeroN) /= 16#01# then            --  PS || 0x01 || salt
                     Good := False;
                  end if;
                  if not Good then
                     return False;
                  end if;
                  for I in 0 .. sLen - 1 loop
                     Salt (I) := DB (DBLen - sLen + I);
                  end loop;
                  --  M' = (0x00)*8 || mHash || salt ; H' = SHA-256(M')
                  for I in 0 .. hLen - 1 loop Mp (8 + I) := mHash (I); end loop;
                  for I in 0 .. sLen - 1 loop Mp (8 + hLen + I) := Salt (I); end loop;
                  Hp := SHA256_BA (Mp);
                  for I in 0 .. hLen - 1 loop
                     if Hp (I) /= H (I) then
                        return False;
                     end if;
                  end loop;
                  return True;
               end;
            end;
         end;
      end;
   end RSA_PSS_SHA256;

   ---------------------------------------------------------------------------
   --  ECDSA / P-256
   ---------------------------------------------------------------------------

   --  SHA-384 of Data, left-truncated to 32 bytes (ECDSA uses the leftmost
   --  256 bits of the digest with a 256-bit group order).
   function SHA384_BA_32 (Data : Byte_Array) return Byte_Array is
      Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Data'Length - 1));
      Dg  : SPARKNaCl.Hashing.SHA384.Digest;
      R   : Byte_Array (0 .. 31);
   begin
      for I in 0 .. Data'Length - 1 loop
         Msg (SPARKNaCl.N32 (I)) := SPARKNaCl.Byte (Data (Data'First + I));
      end loop;
      Dg := SPARKNaCl.Hashing.SHA384.Hash (Msg);
      for I in 0 .. 31 loop
         R (I) := U8 (Dg (SPARKNaCl.Index_32 (I)));
      end loop;
      return R;
   end SHA384_BA_32;

   function To_P256 (B : Byte_Array) return P256.Bytes_32 is
      R : P256.Bytes_32;
   begin
      for I in 0 .. 31 loop
         R (I) := P256.Byte (B (B'First + I));
      end loop;
      return R;
   end To_P256;

   --  Read a DER INTEGER at Pos (tag 0x02), big-endian, into a 32-byte right-aligned
   --  value (leading zero sign byte dropped, short values left-padded).  Advances Pos.
   procedure DER_Int (Buf : Byte_Array; Pos : in out Natural; Last : Natural;
                      Out32 : out P256.Bytes_32; Ok : in out Boolean) is
      Len, First, Vlen : Natural;
   begin
      Out32 := (others => 0);
      if not Ok or else Pos + 1 > Last or else Buf (Pos) /= 16#02# then
         Ok := False;  return;
      end if;
      Len := Natural (Buf (Pos + 1));               --  r, s < 128 bytes => short form
      Pos := Pos + 2;
      if Len = 0 or else Pos + Len - 1 > Last then
         Ok := False;  return;
      end if;
      First := Pos;  Vlen := Len;
      while Vlen > 0 and then Buf (First) = 0 loop   --  drop leading zero bytes
         First := First + 1;  Vlen := Vlen - 1;
      end loop;
      if Vlen > 32 then
         Ok := False;  return;
      end if;
      for I in 0 .. Vlen - 1 loop
         Out32 (32 - Vlen + I) := P256.Byte (Buf (First + I));
      end loop;
      Pos := Pos + Len;
   end DER_Int;

   --  Verify ECDSA(SHA-256/384)/P-256 of Hash32 with signature Sig_DER under
   --  (Pub_X, Pub_Y).  Sig_DER = SEQUENCE { r INTEGER, s INTEGER }.
   function ECDSA_Core (Hash32 : Byte_Array; Sig_DER, Pub_X, Pub_Y : Byte_Array)
                        return Boolean
   is
      Pos    : Natural;
      Ok     : Boolean := True;
      R32, S32 : P256.Bytes_32;
   begin
      if Sig_DER'Length < 8 or else Pub_X'Length /= 32 or else Pub_Y'Length /= 32
        or else Sig_DER (Sig_DER'First) /= 16#30#
      then
         return False;
      end if;
      Pos := Sig_DER'First + 2;                      --  past SEQUENCE tag + length
      DER_Int (Sig_DER, Pos, Sig_DER'Last, R32, Ok);
      DER_Int (Sig_DER, Pos, Sig_DER'Last, S32, Ok);
      if not Ok then
         return False;
      end if;
      return P256.Verify (To_P256 (Pub_X), To_P256 (Pub_Y), To_P256 (Hash32), R32, S32);
   end ECDSA_Core;

   function ECDSA_P256_SHA256
     (Message, Sig_DER, Pub_X, Pub_Y : X509.Byte_Array) return Boolean is
     (ECDSA_Core (SHA256_BA (Message), Sig_DER, Pub_X, Pub_Y));

   function ECDSA_P256_SHA384
     (Message, Sig_DER, Pub_X, Pub_Y : X509.Byte_Array) return Boolean is
     (ECDSA_Core (SHA384_BA_32 (Message), Sig_DER, Pub_X, Pub_Y));

end Cert_Verify;
